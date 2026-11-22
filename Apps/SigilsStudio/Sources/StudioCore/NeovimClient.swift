import Foundation
import MessagePack

public struct BufferSnapshot: Sendable {
    public let source: String
    public let modified: Bool
    public let name: String
}

public struct EditorSnapshot: Sendable {
    public let source: String
    public let cursorLine: Int
}

@MainActor
public final class NeovimClient {
    public var onGrid: ((EditorGrid) -> Void)?
    public var onBuffer: ((BufferSnapshot) -> Void)?
    public var onFailure: ((StudioError) -> Void)?
    public var onStderr: ((String) -> Void)?
    public private(set) var ready = false
    public var running: Bool { process.isRunning }

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var stream = MessageStream()
    private var grid = EditorGrid()
    private var nextID = 0
    private var stopping = false
    private var started = false
    private var pending: [Int: Pending] = [:]
    private var expired: Set<Int> = []
    private var inputQueue: [String] = []
    private var sendingInput = false

    private struct Pending {
        let completion: (Result<MessagePackValue, StudioError>) -> Void
        let timeout: DispatchWorkItem
    }

    public init() {}

    public static func executable(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        if let configured = environment["SIGILS_NVIM"] {
            guard FileManager.default.isExecutableFile(atPath: configured) else {
                throw StudioError.transport("SIGILS_NVIM is not executable: \(configured)")
            }
            return URL(fileURLWithPath: configured)
        }
        #if os(Windows)
        let separator: Character = ";"
        let name = "nvim.exe"
        #else
        let separator: Character = ":"
        let name = "nvim"
        #endif
        for directory in (environment["PATH"] ?? "").split(separator: separator, omittingEmptySubsequences: false) {
            let url = URL(fileURLWithPath: directory.isEmpty ? "." : String(directory))
                .appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw StudioError.transport("Neovim is not on PATH. Install it or set SIGILS_NVIM to its executable.")
    }

    public func start(
        executable: URL, width: Int, height: Int,
        completion: @escaping (Result<Void, StudioError>) -> Void
    ) {
        guard !started else {
            completion(.failure(.transport("A Neovim client can only be started once")))
            return
        }
        started = true
        process.executableURL = executable
        process.arguments = ["--embed", "-u", "NONE", "-i", "NONE", "--cmd", "set noswapfile"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { self?.receive(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            let message = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                if !message.isEmpty { self?.onStderr?(message) }
            }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            DispatchQueue.main.async {
                guard let self, !self.stopping else { return }
                self.fail(.transport("Neovim exited with status \(status)"))
            }
        }
        do {
            try process.run()
        } catch {
            stop()
            completion(.failure(.transport(String(describing: error))))
            return
        }
        request("nvim_get_api_info", []) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let info):
                do {
                    let values = try info.elements()
                    guard values.count >= 2, let metadata = values[1].dictionaryValue,
                          let version = metadata[.string("version")]?.dictionaryValue,
                          let major = version[.string("major")], let minor = version[.string("minor")] else {
                        throw StudioError.protocolError("Missing API version metadata")
                    }
                    guard try major.integer() > 0 || minor.integer() >= 10 else {
                        throw StudioError.remote("Sigils Studio requires Neovim 0.10 or newer")
                    }
                } catch {
                    completion(.failure(.protocolError(String(describing: error))))
                    return
                }
                self.request("nvim_ui_attach", [
                    .int(Int64(width)), .int(Int64(height)),
                    .map([.string("rgb"): .bool(true), .string("ext_linegrid"): .bool(true)]),
                ]) { [weak self] attached in
                    guard let self else { return }
                    switch attached {
                    case .failure(let error): completion(.failure(error))
                    case .success:
                        self.request("nvim_exec_lua", [.string(Self.configure), .array([])]) { [weak self] configured in
                            guard let self else { return }
                            switch configured {
                            case .failure(let error): completion(.failure(error))
                            case .success:
                                self.ready = true
                                completion(.success(()))
                            }
                        }
                    }
                }
            }
        }
    }

    public func source(completion: @escaping (Result<String, StudioError>) -> Void) {
        request("nvim_buf_get_lines", [.int(0), .int(0), .int(-1), .bool(false)]) { result in
            completion(result.flatMap { value in
                do { return .success(try value.elements().map { try $0.text() }.joined(separator: "\n")) }
                catch { return .failure(.protocolError(String(describing: error))) }
            })
        }
    }

    public func snapshot(completion: @escaping (Result<EditorSnapshot, StudioError>) -> Void) {
        request("nvim_exec_lua", [
            .string("return {vim.api.nvim_buf_get_lines(0, 0, -1, false), vim.api.nvim_win_get_cursor(0)[1]}"),
            .array([]),
        ]) { result in
            completion(result.flatMap { value in
                do {
                    let values = try value.elements()
                    guard values.count == 2 else { throw StudioError.protocolError("Malformed editor snapshot") }
                    return .success(EditorSnapshot(
                        source: try values[0].elements().map { try $0.text() }.joined(separator: "\n"),
                        cursorLine: try values[1].integer()
                    ))
                } catch { return .failure(.protocolError(String(describing: error))) }
            })
        }
    }

    public func markExecution(line: Int?) {
        let lua = """
        local line = ...
        local ns = vim.api.nvim_create_namespace('SigilsExecution')
        vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
        if type(line) == 'number' and line > 0 and line <= vim.api.nvim_buf_line_count(0) then
          vim.api.nvim_buf_set_extmark(0, ns, line - 1, 0, {
            sign_text = '>', sign_hl_group = 'DiagnosticInfo', line_hl_group = 'Visual'
          })
        end
        """
        request("nvim_exec_lua", [
            .string(lua), .array([line.map { .int(Int64($0)) } ?? .nil]),
        ], completion: report)
    }

    public func setSource(_ source: String, completion: @escaping (Result<Void, StudioError>) -> Void) {
        let lines = source.components(separatedBy: "\n").map(MessagePackValue.string)
        request("nvim_buf_set_lines", [.int(0), .int(0), .int(-1), .bool(false), .array(lines)]) { result in
            completion(result.map { _ in () })
        }
    }

    public func open(_ path: String, completion: @escaping (Result<Void, StudioError>) -> Void) {
        command("edit", arguments: [path], completion: completion)
    }

    public func save(to path: String? = nil, completion: @escaping (Result<Void, StudioError>) -> Void) {
        command("write", arguments: path.map { [$0] } ?? [], completion: completion)
    }

    public func resize(width: Int, height: Int) {
        request("nvim_ui_try_resize", [.int(Int64(width)), .int(Int64(height))], completion: report)
    }

    public func input(_ keys: String) {
        guard !stopping else { onFailure?(.stopped); return }
        inputQueue.append(keys)
        sendNextInput()
    }

    public func paste(_ text: String) {
        request("nvim_paste", [.string(text), .bool(false), .int(-1)]) { [weak self] result in
            switch result {
            case .failure(let error): self?.onFailure?(error)
            case .success(let value):
                if value.boolValue != true { self?.onFailure?(.remote("Neovim cancelled the paste")) }
            }
        }
    }

    public func copySelection(completion: @escaping (Result<String, StudioError>) -> Void) {
        let lua = """
        local mode = vim.fn.mode()
        if mode ~= 'v' and mode ~= 'V' and mode ~= '\\22' then
          error('Select text in visual mode before copying')
        end
        vim.cmd('normal! y')
        return vim.fn.getreg('"')
        """
        request("nvim_exec_lua", [.string(lua), .array([])]) { result in
            completion(result.flatMap { value in
                do { return .success(try value.text()) }
                catch { return .failure(.protocolError(String(describing: error))) }
            })
        }
    }

    public func mouse(button: String, action: String, row: Int, column: Int) {
        request("nvim_input_mouse", [
            .string(button), .string(action), .string(""), .int(1), .int(Int64(row)), .int(Int64(column)),
        ], completion: report)
    }

    public func stop() {
        stop(reason: .stopped)
    }

    private func stop(reason: StudioError) {
        guard !stopping else { return }
        stopping = true
        ready = false
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        let requests = pending
        pending.removeAll()
        for item in requests.values {
            item.timeout.cancel()
            item.completion(.failure(reason))
        }
        do { try input.fileHandleForWriting.close() }
        catch { onFailure?(.transport(String(describing: error))) }
        if process.isRunning { process.terminate() }
    }

    private func command(
        _ name: String, arguments: [String],
        completion: @escaping (Result<Void, StudioError>) -> Void
    ) {
        request("nvim_cmd", [
            .map([.string("cmd"): .string(name), .string("args"): .array(arguments.map(MessagePackValue.string))]),
            .map([:]),
        ]) { result in completion(result.map { _ in () }) }
    }

    private func sendNextInput() {
        guard !sendingInput, let keys = inputQueue.first else { return }
        sendingInput = true
        request("nvim_input", [.string(keys)]) { [weak self] result in
            guard let self else { return }
            self.sendingInput = false
            switch result {
            case .failure(let error):
                self.inputQueue.removeAll()
                self.onFailure?(error)
            case .success(let value):
                do {
                    let count = try value.integer()
                    let bytes = Array(keys.utf8)
                    guard count > 0, count <= bytes.count,
                          let remainder = String(bytes: bytes.dropFirst(count), encoding: .utf8) else {
                        throw StudioError.protocolError("Invalid input acknowledgement")
                    }
                    self.inputQueue.removeFirst()
                    if !remainder.isEmpty { self.inputQueue.insert(remainder, at: 0) }
                    self.sendNextInput()
                } catch {
                    self.inputQueue.removeAll()
                    self.onFailure?(.protocolError(String(describing: error)))
                }
            }
        }
    }

    private func request(
        _ method: String, _ arguments: [MessagePackValue],
        completion: @escaping (Result<MessagePackValue, StudioError>) -> Void
    ) {
        guard started, !stopping else { completion(.failure(.stopped)); return }
        let id = nextID
        nextID += 1
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, let item = self.pending.removeValue(forKey: id) else { return }
            self.expired.insert(id)
            item.completion(.failure(.timeout(method)))
        }
        pending[id] = Pending(completion: completion, timeout: timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
        do {
            try input.fileHandleForWriting.write(contentsOf:
                pack(.array([.int(0), .int(Int64(id)), .string(method), .array(arguments)])))
        } catch {
            pending.removeValue(forKey: id)?.timeout.cancel()
            completion(.failure(.transport(String(describing: error))))
        }
    }

    private func receive(_ data: Data) {
        guard !stopping else { return }
        do {
            if data.isEmpty {
                try stream.finish()
                fail(.transport("Neovim closed its RPC channel"))
                return
            }
            for value in try stream.append(data) {
                let message = try value.elements()
                guard let first = message.first else { throw StudioError.protocolError("Empty RPC message") }
                switch try first.integer() {
                case 1:
                    guard message.count == 4 else { throw StudioError.protocolError("Malformed RPC response") }
                    let id = try message[1].integer()
                    guard let item = pending.removeValue(forKey: id) else {
                        if expired.remove(id) != nil { continue }
                        throw StudioError.protocolError("Response to unknown request \(id)")
                    }
                    item.timeout.cancel()
                    if message[2].isNil { item.completion(.success(message[3])) }
                    else { item.completion(.failure(.remote(message[2].description))) }
                case 2:
                    guard message.count == 3 else { throw StudioError.protocolError("Malformed notification") }
                    let method = try message[1].text()
                    let arguments = try message[2].elements()
                    if method == "redraw" {
                        try grid.apply(arguments) { [weak self] in self?.onGrid?($0) }
                    } else if method == "sigils_buffer" {
                        guard arguments.count == 3, let modified = arguments[1].boolValue else {
                            throw StudioError.protocolError("Malformed buffer notification")
                        }
                        onBuffer?(BufferSnapshot(
                            source: try arguments[0].elements().map { try $0.text() }.joined(separator: "\n"),
                            modified: modified, name: try arguments[2].text()
                        ))
                    }
                case 0:
                    guard message.count == 4 else { throw StudioError.protocolError("Malformed RPC request") }
                    let id = try message[1].integer()
                    try input.fileHandleForWriting.write(contentsOf:
                        pack(.array([.int(1), .int(Int64(id)),
                                     .string("Sigils Studio does not implement remote client calls"), .nil])))
                default:
                    throw StudioError.protocolError("Unknown RPC message type")
                }
            }
        } catch {
            fail(.protocolError(String(describing: error)))
        }
    }

    private func report(_ result: Result<MessagePackValue, StudioError>) {
        if case .failure(let error) = result { onFailure?(error) }
    }

    private func fail(_ error: StudioError) {
        guard !stopping else { return }
        ready = false
        onFailure?(error)
        stop(reason: error)
    }

    private static let configure = """
    vim.o.termguicolors = true
    vim.o.number = true
    vim.o.mouse = 'a'
    vim.o.hidden = false
    local function notify()
      vim.rpcnotify(1, 'sigils_buffer', vim.api.nvim_buf_get_lines(0, 0, -1, false),
                    vim.bo.modified, vim.api.nvim_buf_get_name(0))
    end
    vim.api.nvim_create_autocmd({'TextChanged', 'TextChangedI', 'BufEnter', 'BufWritePost', 'BufFilePost'}, {
      group = vim.api.nvim_create_augroup('SigilsStudio', {clear = true}), callback = notify
    })
    notify()
    """
}
