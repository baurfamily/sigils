import Foundation
import StudioCore
import SwiftCrossUI
#if os(macOS)
import AppKit
#endif

@MainActor
final class WorkspaceModel: SwiftCrossUI.ObservableObject {
    @SwiftCrossUI.Published var grid = EditorGrid()
    @SwiftCrossUI.Published var path = ""
    @SwiftCrossUI.Published var ready = false
    @SwiftCrossUI.Published var running = false
    @SwiftCrossUI.Published var error: String?
    @SwiftCrossUI.Published var result: ScriptRun?
    @SwiftCrossUI.Published var status = "Starting Neovim..."
    @SwiftCrossUI.Published private(set) var debug: DebugRun?
    @SwiftCrossUI.Published private(set) var debugInvalidated = false

    let client = NeovimClient()
    private var started = false
    private var stopped = false
    private var currentSource = ""
    private var executedSource: String?
    private var bufferName = ""
    private var draftURL: URL?
    private var columns = 80
    private var rows = 24
    private let recoveryDirectory: URL?
    private let initialPath: String?
    private var operationID = UUID()
    private var debugStopped = false
    #if os(macOS)
    private var shortcutMonitor: Any?
    #endif

    var canStep: Bool { ready && !running && !debugInvalidated && !(debug?.isFinished ?? false) }

    init(recoveryDirectory: URL? = nil, initialPath: String? = nil) {
        self.recoveryDirectory = recoveryDirectory
        self.initialPath = initialPath
    }

    func start() {
        guard !started else { return }
        started = true
        #if !os(macOS)
        report("The editor viewport currently requires macOS. Linux/Windows native adapters are not implemented yet.")
        return
        #else
        do {
            let directory: URL
            if let recoveryDirectory {
                directory = recoveryDirectory
            } else {
                guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                    throw StudioError.transport("Cannot locate the user application support directory")
                }
                directory = support.appendingPathComponent("SigilsStudio", isDirectory: true)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let draft = directory.appendingPathComponent("draft.sigils")
            draftURL = draft
            let source: String
            if initialPath == nil, FileManager.default.fileExists(atPath: draft.path) {
                source = try String(contentsOf: draft, encoding: .utf8)
            } else {
                source = "10\n20\n?@0\n+\n!print"
            }
            client.onGrid = { [weak self] in self?.grid = $0 }
            client.onBuffer = { [weak self] in self?.bufferChanged($0) }
            client.onFailure = { [weak self] in self?.report($0.description) }
            client.onStderr = { [weak self] message in
                self?.report("Neovim stderr: \(message)")
            }
            client.start(executable: try NeovimClient.executable(), width: columns, height: rows) { [weak self] result in
                guard let self, !self.stopped else { return }
                switch result {
                case .failure(let error):
                    self.report(error.description)
                    self.client.stop()
                case .success:
                    let completed: (Result<Void, StudioError>) -> Void = { [weak self] result in
                        guard let self, !self.stopped else { return }
                        switch result {
                        case .failure(let error): self.report(error.description)
                        case .success:
                            self.ready = true
                            self.status = "Neovim · \(self.grid.mode) · Run starts with a fresh stack and bindings"
                        }
                    }
                    if let initialPath = self.initialPath { self.client.open(initialPath, completion: completed) }
                    else { self.client.setSource(source, completion: completed) }
                }
            }
        } catch {
            report(String(describing: error))
        }
        #endif
    }

    func stop() {
        operationID = UUID()
        #if os(macOS)
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        #endif
        stopped = true
        ready = false
        client.stop()
    }

    func resize(columns: Int, rows: Int) {
        guard columns != self.columns || rows != self.rows else { return }
        self.columns = columns
        self.rows = rows
        if client.ready { client.resize(width: columns, height: rows) }
    }

    func open() {
        guard !path.isEmpty else { report("Enter a file path, or use :e path in Neovim."); return }
        client.open(path, completion: completed)
    }

    func save() {
        client.save(to: bufferName.isEmpty && !path.isEmpty ? path : nil, completion: completed)
    }

    func run() {
        guard ready, !running else { return }
        debug = nil
        debugInvalidated = false
        debugStopped = false
        client.markExecution(line: nil)
        running = true
        error = nil
        let id = UUID()
        operationID = id
        client.source { [weak self] response in
            guard let self, self.operationID == id, !self.stopped else { return }
            switch response {
            case .failure(let error):
                self.running = false
                self.report(error.description)
            case .success(let source):
                self.executedSource = source
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let result = ScriptRun.execute(source)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.stopped, self.operationID == id else { return }
                        self.result = result
                        self.running = false
                        self.updateStatus()
                    }
                }
            }
        }
    }

    enum DebugAction: Sendable {
        case start, instruction, line, cursor
    }

    func debugAction(_ action: DebugAction) {
        guard ready, !running else { return }
        if action != .start, debugInvalidated {
            report("The debug source changed. Start Debug again before stepping.")
            return
        }
        if action != .start, debug?.isFinished == true {
            report("Debug run has finished. Start Debug to restart.")
            return
        }
        error = nil
        running = true
        let id = UUID()
        operationID = id
        client.snapshot { [weak self] response in
            guard let self, self.operationID == id, !self.stopped else { return }
            switch response {
            case .failure(let error):
                self.running = false
                self.report(error.description)
            case .success(let snapshot):
                if action != .start, let debug = self.debug, debug.source != snapshot.source {
                    self.running = false
                    self.debugInvalidated = true
                    self.client.markExecution(line: nil)
                    self.report("The debug source changed. Start Debug again before stepping.")
                    self.updateStatus()
                    return
                }
                let run = action == .start ? DebugRun(source: snapshot.source)
                    : (self.debug ?? DebugRun(source: snapshot.source))
                if action == .cursor, let next = run.nextLocation, snapshot.cursorLine < next.line {
                    self.running = false
                    self.report("The cursor is behind the execution position. Start Debug to restart.")
                    return
                }
                self.executedSource = snapshot.source
                self.debugStopped = false
                let prepared = run
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    var advanced = prepared
                    switch action {
                    case .start: break
                    case .instruction: advanced.stepInstruction()
                    case .line: advanced.stepLine()
                    case .cursor: advanced.runToLine(snapshot.cursorLine)
                    }
                    let completed = advanced
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.stopped, self.operationID == id else { return }
                        self.running = false
                        self.debug = completed
                        self.debugInvalidated = self.currentSource != completed.source
                        self.result = completed.result
                        self.client.markExecution(line: self.debugInvalidated ? nil
                            : (completed.nextLocation?.line
                                ?? (completed.result.diagnostic == nil ? nil : completed.lastInstruction?.start.line)))
                        self.updateStatus()
                    }
                }
            }
        }
    }

    func stopDebug() {
        operationID = UUID()
        running = false
        debug = nil
        debugInvalidated = false
        debugStopped = true
        if client.ready { client.markExecution(line: nil) }
        updateStatus()
    }

    #if os(macOS)
    func installShortcuts(in window: NSWindow) {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            return self.handleShortcut(event) ? nil : event
        }
    }

    @discardableResult
    func handleShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        guard modifiers == .command || modifiers == [.command, .shift] else { return false }
        let shifted = modifiers.contains(.shift)
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch (key, shifted) {
        case ("r", false), ("r", true): run()
        case ("d", false): debugAction(.start)
        case ("j", false): debugAction(.instruction)
        case ("j", true): debugAction(.line)
        case ("c", true): debugAction(.cursor)
        case (".", false): stopDebug()
        case ("s", false): if ready { save() }
        default: return false
        }
        return true
    }
    #endif

    func report(_ message: String) {
        error = message
        ready = client.ready && !stopped
        if !ready { status = "Editor unavailable" }
    }

    private func completed(_ result: Result<Void, StudioError>) {
        switch result {
        case .failure(let error): report(error.description)
        case .success:
            error = nil
            updateStatus()
        }
    }

    private func bufferChanged(_ buffer: BufferSnapshot) {
        currentSource = buffer.source
        if let debug, debug.source != buffer.source, !debugInvalidated {
            debugInvalidated = true
            if client.ready { client.markExecution(line: nil) }
        }
        if buffer.name != bufferName {
            bufferName = buffer.name
            path = buffer.name
        }
        if buffer.modified, let draftURL {
            do { try buffer.source.write(to: draftURL, atomically: true, encoding: .utf8) }
            catch {
                report("Unable to preserve the recovery draft: \(error)")
                client.stop()
                ready = false
                return
            }
        }
        updateStatus()
    }

    private func updateStatus() {
        if debugInvalidated {
            status = "Buffer changed - Start Debug again; paused results are stale"
        } else if let debug {
            if let next = debug.nextLocation {
                status = "Paused before \(next.line):\(next.column) - Step Instruction or Step Line"
            } else {
                status = debug.result.diagnostic == nil ? "Debug complete" : "Debug stopped on a language error"
            }
        } else if debugStopped {
            status = "Execution stopped - displayed results are from the last completed step/run"
        } else if let executedSource, executedSource != currentSource {
            status = "Buffer changed · stack/output belong to the previous Run"
        } else if result != nil {
            status = result?.diagnostic == nil ? "Run complete · fresh stack and bindings" : "Run stopped on a language error"
        } else if ready {
            status = "Neovim · \(grid.mode) · draft preserved in Application Support/SigilsStudio/draft.sigils"
        }
    }
}
