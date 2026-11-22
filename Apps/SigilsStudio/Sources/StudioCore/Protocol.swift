import Foundation
import MessagePack

public enum StudioError: Error, Sendable, CustomStringConvertible {
    case protocolError(String)
    case transport(String)
    case remote(String)
    case timeout(String)
    case stopped

    public var description: String {
        switch self {
        case .protocolError(let message): "Neovim protocol: \(message)"
        case .transport(let message): "Neovim transport: \(message)"
        case .remote(let message): "Neovim: \(message)"
        case .timeout(let method): "Neovim request timed out: \(method)"
        case .stopped: "Neovim has stopped"
        }
    }
}

struct MessageStream {
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [MessagePackValue] {
        buffer.append(data)
        guard buffer.count <= 8 * 1024 * 1024 else {
            throw StudioError.protocolError("RPC buffer exceeds 8 MiB")
        }
        var messages: [MessagePackValue] = []
        while !buffer.isEmpty {
            do {
                let decoded = try unpack(buffer)
                messages.append(decoded.value)
                buffer = decoded.remainder
            } catch MessagePackError.insufficientData {
                break
            }
        }
        return messages
    }

    func finish() throws {
        guard buffer.isEmpty else {
            throw StudioError.protocolError("RPC stream ended inside a message")
        }
    }
}

extension MessagePackValue {
    func integer() throws -> Int {
        let value: Int?
        switch self {
        case .int(let number): value = Int(exactly: number)
        case .uint(let number): value = Int(exactly: number)
        default: value = nil
        }
        guard let value else { throw StudioError.protocolError("Expected an integer, got \(self)") }
        return value
    }

    func text() throws -> String {
        guard case .string(let value) = self else {
            throw StudioError.protocolError("Expected a string, got \(self)")
        }
        return value
    }

    func elements() throws -> [MessagePackValue] {
        guard case .array(let value) = self else {
            throw StudioError.protocolError("Expected an array, got \(self)")
        }
        return value
    }
}
