import Foundation

public struct FunctionValue: Equatable, Sendable {
    internal let identity: UUID
    internal let name: String?
    internal let inputCount: Int?
    internal let copiesInputs: Bool
    internal let outputCount: Int?
    internal let body: FunctionBody
    internal let captured: [String: Value]
    internal let parentScope: Int

    public static func == (lhs: FunctionValue, rhs: FunctionValue) -> Bool {
        lhs.identity == rhs.identity
    }

    public var description: String {
        name.map { "<function \($0)>" } ?? "<function>"
    }
}

internal struct FunctionBody: Sendable {
    let characters: [Character]
    let locations: [SourceLocation]
}

internal struct LexicalScope: Sendable {
    var bindings: [String: Value]
    let parent: Int?
}

internal struct FunctionContext: Sendable {
    var scopes: [Int: LexicalScope] = [0: LexicalScope(bindings: [:], parent: nil)]
    var nextScope = 1
    var activeCalls: [UUID] = []

    mutating func makeScope(bindings: [String: Value], parent: Int) -> Int {
        let id = nextScope
        nextScope += 1
        scopes[id] = LexicalScope(bindings: bindings, parent: parent)
        return id
    }

    /// Keep escaped environments, but not every completed call in a long-lived REPL.
    mutating func collect(stack: [Value]) {
        var reachable: Set<Int> = [0]
        var scopeQueue = [0]
        var values = stack
        var functions: Set<UUID> = []
        while !scopeQueue.isEmpty || !values.isEmpty {
            if let scope = scopeQueue.popLast(), let environment = scopes[scope] {
                values.append(contentsOf: environment.bindings.values)
                if let parent = environment.parent, reachable.insert(parent).inserted {
                    scopeQueue.append(parent)
                }
            } else if let value = values.popLast(), case .function(let function) = value,
                      functions.insert(function.identity).inserted {
                values.append(contentsOf: function.captured.values)
                if reachable.insert(function.parentScope).inserted {
                    scopeQueue.append(function.parentScope)
                }
            }
        }
        scopes = scopes.filter { reachable.contains($0.key) }
    }
}
