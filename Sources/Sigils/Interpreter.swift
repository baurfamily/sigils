public enum Value: Equatable, Sendable, CustomStringConvertible {
    case number(Double)
    case string(String)
    case null
    case error(LanguageError)

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

    public init() {}

    public mutating func execute(_ source: String) throws -> String {
        let result = evaluate(source)
        if let error = result.error { throw error }
        return result.output
    }

    /// Stops at the first error while retaining successful instructions and output.
    public mutating func evaluate(_ source: String) -> ExecutionResult {
        var session = ExecutionSession(source: source, stack: stack, variables: variables)
        while !session.isFinished { _ = session.step() }
        stack = session.stack
        variables = session.variables
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
    private var parser: Parser
    public private(set) var output = ""
    public private(set) var error: LanguageError?
    public private(set) var lastInstruction: SourceSpan?

    public var stack: [Value] { parser.stack }
    public var variables: [String: Value] { parser.variables }
    public var nextLocation: SourceLocation? {
        guard error == nil, let position = parser.nextPosition else { return nil }
        return parser.locations[position]
    }
    public var isFinished: Bool { nextLocation == nil }

    public init(source: String) {
        self.init(source: source, stack: [], variables: [:])
    }

    fileprivate init(source: String, stack: [Value], variables: [String: Value]) {
        parser = Parser(source: source, stack: stack, variables: variables)
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

private struct Parser: Sendable {
    let characters: [Character]
    let locations: [SourceLocation]
    var position = 0
    var stack: [Value]
    var variables: [String: Value]
    var instructionStart = 0

    init(source: String, stack: [Value], variables: [String: Value]) {
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
        self.variables = variables
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
            let start = position
            while position < characters.count,
                  characters[position].isLetter || characters[position].isNumber
                    || characters[position] == "_" {
                position += 1
            }
            let name = String(characters[start..<position])
            guard name == "print" else {
                throw error("Unknown function !\(name)", code: .unknownFunction)
            }
            guard let value = stack.popLast() else {
                throw error("!print needs a value on the stack", code: .stackUnderflow)
            }
            if value != .null { output += value.description + "\n" }
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
        guard position < characters.count, isIdentifierStart(characters[position]) else {
            let code: ErrorCode = position == characters.count || characters[position].isWhitespace
                ? .missingAttachedDestination : .invalidDestination
            throw error("Attach a destination name to the arrow: ->x", code: code)
        }
        let name = identifier()
        guard let value = stack.last else {
            throw error("Storage needs a value on the stack", code: .stackUnderflow)
        }
        variables[name] = value
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
        if isIdentifierStart(characters[position]) {
            value = try variable(named: identifier())
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
        guard let value = variables[name] else {
            throw error("Undefined variable \(name)", code: .undefinedVariable)
        }
        return value
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
