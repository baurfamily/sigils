import Foundation

public enum Value: Equatable, Sendable, CustomStringConvertible {
    case number(Double)
    case string(String)
    case null
    case error(LanguageError)
    case function(FunctionValue)

    public var description: String {
        switch self {
        case .number(let number):
            let text = String(number)
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        case .string(let string):
            return string
        case .null:
            return "null"
        case .error(let error):
            return "err:<\(error.code.rawValue), \(error.line)>"
        case .function(let function):
            return function.description
        }
    }
}

public enum ErrorCode: String, Sendable {
    case syntaxError = "syntax-error"
    case stackUnderflow = "stack-underflow"
    case typeError = "type-error"
    case numericOverflow = "numeric-overflow"
    case unknownFunction = "unknown-function"
    case undefinedVariable = "undefined-variable"
    case missingAttachedDestination = "missing-attached-destination"
    case invalidDestination = "invalid-destination"
    case invalidStackIndex = "invalid-stack-index"
    case stackIndexOutOfBounds = "stack-index-out-of-bounds"
}

public struct LanguageError: Error, Equatable, Sendable, CustomStringConvertible {
    public let code: ErrorCode
    public let line: Int
    public let column: Int
    public let message: String

    public var description: String {
        "\(line):\(column): \(code.rawValue): \(message)"
    }
}

public struct ExecutionResult: Sendable {
    public let output: String
    public let error: LanguageError?
}

public struct Interpreter {
    public private(set) var stack: [Value] = []
    public private(set) var variables: [String: Value] = [:]
    private var context = FunctionContext()

    public init() {}

    public mutating func execute(_ source: String) throws -> String {
        let result = evaluate(source)
        if let error = result.error { throw error }
        return result.output
    }

    /// Stops at the first error while retaining successful instructions and output.
    public mutating func evaluate(_ source: String) -> ExecutionResult {
        var session = ExecutionSession(source: source, stack: stack, context: context)
        while !session.isFinished { _ = session.step() }
        stack = session.stack
        variables = session.variables
        context = session.parser.context
        context.collect(stack: stack)
        return ExecutionResult(output: session.output, error: session.error)
    }

    public mutating func executeInteractive(_ source: String) -> ExecutionResult {
        let result = evaluate(source)
        if let error = result.error { stack.append(.error(error)) }
        return result
    }
}

public struct SourceLocation: Equatable, Sendable {
    public let line: Int
    public let column: Int
}

public struct SourceSpan: Equatable, Sendable {
    public let start: SourceLocation
    public let end: SourceLocation
}

/// Executes an immutable source snapshot, pausing between complete instructions.
public struct ExecutionSession: Sendable {
    fileprivate var parser: Parser
    public private(set) var output = ""
    public private(set) var error: LanguageError?
    public private(set) var lastInstruction: SourceSpan?

    public var stack: [Value] { parser.stack }
    public var variables: [String: Value] { parser.variables }
    public var failureLocation: SourceLocation? {
        error.map { SourceLocation(line: $0.line, column: $0.column) }
    }
    public var nextLocation: SourceLocation? {
        guard error == nil, let position = parser.nextPosition else { return nil }
        return parser.locations[position]
    }
    public var isFinished: Bool { nextLocation == nil }

    public init(source: String) {
        self.init(source: source, stack: [], context: FunctionContext())
    }

    fileprivate init(source: String, stack: [Value], context: FunctionContext) {
        parser = Parser(source: source, stack: stack, context: context)
    }

    /// Returns only this instruction's output; `output` retains the complete run.
    @discardableResult
    public mutating func step() -> ExecutionResult {
        guard !isFinished else { return ExecutionResult(output: "", error: error) }
        parser.skipWhitespace()
        parser.instructionStart = parser.position
        let start = parser.locations[parser.position]
        var emitted = ""
        do {
            try parser.instruction(output: &emitted)
        } catch {
            self.error = error
        }
        lastInstruction = SourceSpan(start: start, end: parser.locations[parser.position])
        output += emitted
        return ExecutionResult(output: emitted, error: error)
    }
}

fileprivate struct Parser: Sendable {
    let characters: [Character]
    let locations: [SourceLocation]
    var position = 0
    var stack: [Value]
    var context: FunctionContext
    let scopeID: Int
    var variables: [String: Value] {
        // Scope IDs are allocated internally and remain live for the active parser.
        context.scopes[scopeID]!.bindings
    }
    var instructionStart = 0

    init(source: String, stack: [Value], context: FunctionContext) {
        characters = Array(source)
        var locations: [SourceLocation] = []
        var line = 1
        var column = 1
        for character in characters {
            locations.append(SourceLocation(line: line, column: column))
            if character.isNewline { line += 1; column = 1 }
            else { column += 1 }
        }
        locations.append(SourceLocation(line: line, column: column))
        self.locations = locations
        self.stack = stack
        self.context = context
        scopeID = 0
    }

    init(body: FunctionBody, stack: [Value], context: FunctionContext, scopeID: Int) {
        characters = body.characters
        locations = body.locations
        self.stack = stack
        self.context = context
        self.scopeID = scopeID
    }

    var nextPosition: Int? {
        var next = position
        while next < characters.count, characters[next].isWhitespace {
            next += 1
        }
        return next < characters.count ? next : nil
    }

    mutating func instruction(output: inout String) throws(LanguageError) {
        switch characters[position] {
        case "{":
            let function = try functionDefinition()
            if let name = function.name {
                try bind(.function(function), named: name, in: scopeID)
            } else {
                stack.append(.function(function))
            }
        case ":":
            let reference = try scopedName()
            stack.append(try variable(named: reference.name, in: reference.scope))
        case "?":
            position += 1
            if position < characters.count, characters[position] == "@" {
                try accessStack(consuming: false)
            } else if position + 1 < characters.count,
                      characters[position] == "-", characters[position + 1] == ">" {
                try store(consuming: false)
            } else {
                throw error("Peek must modify attached storage or stack access: ?->x or ?@0")
            }
        case "@":
            try accessStack(consuming: true)
        case "-" where position + 1 < characters.count && characters[position + 1] == ">":
            try store(consuming: true)
        case "-" where position + 1 < characters.count && isDigit(characters[position + 1]):
            stack.append(try scalar())
        case "+", "-", "*", "/":
            let operation = characters[position]
            guard stack.count >= 2 else {
                throw error("Operator \(operation) needs two values on the stack", code: .stackUnderflow)
            }
            let left = stack[stack.count - 2]
            let right = stack[stack.count - 1]
            let result = try evaluate(operation, left: left, right: right)
            stack.removeLast(2)
            stack.append(result)
            position += 1
        case "!":
            position += 1
            if position < characters.count, characters[position] == "{" {
                let function = try functionDefinition()
                guard function.name == nil else {
                    throw error("An immediate call requires an anonymous function")
                }
                try invoke(function, output: &output)
                return
            }
            let reference: (name: String, scope: Int)
            if position < characters.count, characters[position] == ":" {
                reference = try scopedName()
            } else {
                reference = (identifier(), scopeID)
            }
            if reference.name == "print", reference.scope == scopeID {
                guard let value = stack.popLast() else {
                    throw error("!print needs a value on the stack", code: .stackUnderflow)
                }
                if value != .null { output += value.description + "\n" }
            } else {
                guard let value = context.scopes[reference.scope]?.bindings[reference.name] else {
                    throw error("Unknown function !\(reference.name)", code: .unknownFunction)
                }
                guard case .function(let function) = value else {
                    throw error("!\(reference.name) requires a function value", code: .typeError)
                }
                try invoke(function, output: &output)
            }
        default:
            if isIdentifierStart(characters[position]) {
                let name = identifier()
                stack.append(try variable(named: name))
            } else {
                stack.append(try scalar())
            }
        }
    }

    mutating func store(consuming: Bool) throws(LanguageError) {
        position += 2
        let inserting = position < characters.count && characters[position] == "?"
        if inserting {
            position += 1
            guard consuming, position < characters.count, characters[position] == "@" else {
                throw error("Insertion currently requires consuming storage: ->?@index")
            }
        }
        if position < characters.count, characters[position] == "@" {
            let index = try stackIndex()
            guard let source = stack.last else {
                throw error("Storage needs a value on the stack", code: .stackUnderflow)
            }
            let destination = try stackPosition(index, count: stack.count + (inserting ? 1 : 0))
            if inserting {
                stack.removeLast()
                // Removing the source shifts only the gap above the original top.
                stack.insert(source, at: min(destination, stack.count))
            } else {
                stack[destination] = source
                if consuming, destination != stack.count - 1 { stack.removeLast() }
            }
            return
        }
        guard position < characters.count,
              isIdentifierStart(characters[position]) || characters[position] == ":" else {
            let code: ErrorCode = position == characters.count || characters[position].isWhitespace
                ? .missingAttachedDestination : .invalidDestination
            throw error("Attach a destination name to the arrow: ->x", code: code)
        }
        let reference = try scopedName()
        guard let value = stack.last else {
            throw error("Storage needs a value on the stack", code: .stackUnderflow)
        }
        try bind(value, named: reference.name, in: reference.scope)
        if consuming { stack.removeLast() }
    }

    mutating func accessStack(consuming: Bool) throws(LanguageError) {
        let index = try stackIndex()
        let position = try stackPosition(index, count: stack.count)
        let value = stack[position]
        if consuming { stack.remove(at: position) }
        stack.append(value)
    }

    mutating func stackIndex() throws(LanguageError) -> Double {
        position += 1
        guard position < characters.count, !characters[position].isWhitespace else {
            throw error("Attach an index to @")
        }
        let value: Value
        if isIdentifierStart(characters[position]) || characters[position] == ":" {
            let reference = try scopedName()
            value = try variable(named: reference.name, in: reference.scope)
        } else {
            value = try scalar()
        }
        guard case .number(let number) = value, number.isFinite,
              number.rounded(.towardZero) == number else {
            throw error("Stack indices must be finite whole numbers", code: .invalidStackIndex)
        }
        return number
    }

    func stackPosition(_ index: Double, count: Int) throws(LanguageError) -> Int {
        guard let index = Int(exactly: index), index >= -count, index < count else {
            throw error("Stack index is out of bounds", code: .stackIndexOutOfBounds)
        }
        return index >= 0 ? count - 1 - index : -index - 1
    }

    func variable(named name: String) throws(LanguageError) -> Value {
        try variable(named: name, in: scopeID)
    }

    func variable(named name: String, in scope: Int) throws(LanguageError) -> Value {
        guard let value = context.scopes[scope]?.bindings[name] else {
            throw error("Undefined variable \(name)", code: .undefinedVariable)
        }
        return value
    }

    mutating func bind(_ value: Value, named name: String, in scope: Int) throws(LanguageError) {
        guard context.scopes[scope] != nil else {
            throw error("The selected lexical scope is unavailable", code: .undefinedVariable)
        }
        context.scopes[scope]?.bindings[name] = value
    }

    mutating func scopedName() throws(LanguageError) -> (name: String, scope: Int) {
        var scope = scopeID
        if position < characters.count, characters[position] == ":" {
            position += 1
            if position < characters.count, characters[position] == ":" {
                position += 1
                scope = 0
            } else {
                guard let parent = context.scopes[scopeID]?.parent else {
                    throw error("The current scope has no parent", code: .undefinedVariable)
                }
                scope = parent
            }
        }
        guard position < characters.count, isIdentifierStart(characters[position]) else {
            throw error("Attach a variable name to its scope prefix")
        }
        return (identifier(), scope)
    }

    mutating func functionDefinition() throws(LanguageError) -> FunctionValue {
        position += 1
        var name: String?
        if position < characters.count, characters[position] == ":" {
            position += 1
            guard position < characters.count, isIdentifierStart(characters[position]) else {
                throw error("Attach a function name to the definition colon")
            }
            name = identifier()
        }
        var copiesInputs = false
        if position < characters.count, characters[position] == "?" {
            copiesInputs = true
            position += 1
            guard position < characters.count, characters[position] == "<" else {
                throw error("A copied input count requires ?<count")
            }
        }
        var inputs: Int?
        if position < characters.count, characters[position] == "<" {
            position += 1
            inputs = try functionCount()
        }
        let bodyStart = position
        var depth = 1
        while position < characters.count {
            let character = characters[position]
            if character == "\"" {
                position += 1
                while position < characters.count, characters[position] != "\"" {
                    guard !characters[position].isNewline else {
                        throw error("Quoted strings must be on one line")
                    }
                    position += 1
                }
                guard position < characters.count else { throw error("Unterminated string in function definition") }
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            position += 1
        }
        guard depth == 0 else { throw error("Unterminated function definition") }
        let bodyEnd = position
        position += 1
        var outputs: Int?
        if inputs != nil {
            guard position < characters.count, characters[position] == ">" else {
                throw error("Private functions require an attached output count: }>count")
            }
            position += 1
            outputs = try functionCount()
        } else if position < characters.count, characters[position] == ">" {
            throw error("Shared-stack functions do not declare an output count")
        }
        return FunctionValue(
            identity: UUID(), name: name, inputCount: inputs, copiesInputs: copiesInputs,
            outputCount: outputs,
            body: FunctionBody(characters: Array(characters[bodyStart..<bodyEnd]),
                               locations: Array(locations[bodyStart...bodyEnd])),
            captured: variables, parentScope: scopeID
        )
    }

    mutating func functionCount() throws(LanguageError) -> Int {
        let start = position
        while position < characters.count, isDigit(characters[position]) { position += 1 }
        guard position > start, let count = Int(String(characters[start..<position])),
              position == characters.count
                || (characters[position] != "." && !isIdentifierStart(characters[position])) else {
            throw error("Function counts must be attached nonnegative integers")
        }
        return count
    }

    mutating func invoke(_ function: FunctionValue, output: inout String) throws(LanguageError) {
        guard !context.activeCalls.contains(function.identity), context.activeCalls.count < 128 else {
            throw error("Recursive calls and call depths over 128 are not supported", code: .typeError)
        }
        guard context.scopes[function.parentScope] != nil else {
            throw error("The function's defining scope is unavailable", code: .undefinedVariable)
        }
        let childStack: [Value]
        if let count = function.inputCount {
            guard stack.count >= count else {
                throw error("Function needs \(count) input values", code: .stackUnderflow)
            }
            childStack = Array(stack.suffix(count))
            if !function.copiesInputs { stack.removeLast(count) }
        } else {
            childStack = stack
        }
        let childScope = context.makeScope(bindings: function.captured, parent: function.parentScope)
        context.activeCalls.append(function.identity)
        var child = Parser(body: function.body, stack: childStack, context: context, scopeID: childScope)
        defer {
            context = child.context
            context.activeCalls.removeLast()
            if function.inputCount == nil { stack = child.stack }
        }
        while let next = child.nextPosition {
            child.position = next
            child.instructionStart = next
            try child.instruction(output: &output)
        }
        if let count = function.outputCount {
            guard child.stack.count >= count else {
                throw error("Function produced fewer than \(count) declared outputs", code: .stackUnderflow)
            }
            stack.append(contentsOf: child.stack.suffix(count))
        }
    }

    func evaluate(_ operation: Character, left: Value, right: Value) throws(LanguageError) -> Value {
        switch (left, right) {
        case (.string(let lhs), .string(let rhs)) where operation == "+":
            return .string(lhs + rhs)
        case (.null, .string(let rhs)) where operation == "+":
            return .string(rhs)
        case (.string(let lhs), .null) where operation == "+":
            return .string(lhs)
        case (.null, .number), (.number, .null), (.null, .null):
            return .null
        case (.number(let lhs), .number(let rhs)):
            let result: Double
            switch operation {
            case "+": result = lhs + rhs
            case "-": result = lhs - rhs
            case "*": result = lhs * rhs
            case "/":
                guard rhs != 0 else { return .null }
                result = lhs / rhs
            default:
                throw error("Unknown operator \(operation)")
            }
            guard result.isFinite else { throw error("Numeric overflow", code: .numericOverflow) }
            return .number(result)
        default:
            throw error(operation == "+"
                        ? "Addition requires two numbers or two strings (null may coerce)"
                        : "Operator \(operation) requires numbers (null may propagate)", code: .typeError)
        }
    }

    mutating func scalar() throws(LanguageError) -> Value {
        guard position < characters.count else { throw error("Expected a value") }
        if characters[position] == "\"" {
            position += 1
            let start = position
            while position < characters.count, characters[position] != "\"" {
                guard !characters[position].isNewline else {
                    throw error("Quoted strings must be on one line")
                }
                position += 1
            }
            guard position < characters.count else { throw error("Unterminated string") }
            let value = String(characters[start..<position])
            position += 1
            return .string(value)
        }

        let start = position
        if characters[position] == "-" { position += 1 }
        let integerStart = position
        while position < characters.count, isDigit(characters[position]) {
            position += 1
        }
        guard position > integerStart else { throw error("Expected a number or quoted string") }
        if position < characters.count, characters[position] == "." {
            position += 1
            let fractionStart = position
            while position < characters.count, isDigit(characters[position]) {
                position += 1
            }
            guard position > fractionStart else { throw error("Expected digits after decimal point") }
        }
        let text = String(characters[start..<position])
        guard let value = Double(text), value.isFinite else {
            throw error("Number is outside the supported range")
        }
        return .number(value)
    }

    mutating func skipWhitespace() {
        while position < characters.count, characters[position].isWhitespace {
            position += 1
        }
    }

    func isDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }

    func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || (character >= "a" && character <= "z")
            || (character >= "A" && character <= "Z")
    }

    mutating func identifier() -> String {
        let start = position
        while position < characters.count,
              isIdentifierStart(characters[position]) || isDigit(characters[position]) {
            position += 1
        }
        return String(characters[start..<position])
    }

    func error(_ message: String, code: ErrorCode = .syntaxError) -> LanguageError {
        let location = locations[instructionStart]
        return LanguageError(code: code, line: location.line, column: location.column, message: message)
    }
}
