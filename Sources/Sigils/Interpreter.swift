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

public struct ExecutionResult {
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
        var parser = Parser(source: source, stack: stack, variables: variables)
        let result = parser.run()
        stack = parser.stack
        variables = parser.variables
        return result
    }

    public mutating func executeInteractive(_ source: String) -> ExecutionResult {
        let result = evaluate(source)
        if let error = result.error { stack.append(.error(error)) }
        return result
    }
}

private struct Parser {
    let characters: [Character]
    var position = 0
    var stack: [Value]
    var variables: [String: Value]
    var instructionStart = 0

    init(source: String, stack: [Value], variables: [String: Value]) {
        characters = Array(source)
        self.stack = stack
        self.variables = variables
    }

    mutating func run() -> ExecutionResult {
        var output = ""
        while true {
            skipWhitespace()
            guard position < characters.count else {
                return ExecutionResult(output: output, error: nil)
            }
            instructionStart = position
            do {
                try instruction(output: &output)
            } catch {
                return ExecutionResult(output: output, error: error)
            }
        }
    }

    mutating func instruction(output: inout String) throws(LanguageError) {
        switch characters[position] {
        case "-" where position + 1 < characters.count && characters[position + 1] == ">":
            position += 2
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
            stack.removeLast()
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
                guard let value = variables[name] else {
                    throw error("Undefined variable \(name)", code: .undefinedVariable)
                }
                stack.append(value)
            } else {
                stack.append(try scalar())
            }
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
        let prefix = characters[..<instructionStart]
        let line = prefix.filter(\.isNewline).count + 1
        let lastNewline = prefix.lastIndex(where: \.isNewline)
        let column = instructionStart - (lastNewline.map { $0 + 1 } ?? 0) + 1
        return LanguageError(code: code, line: line, column: column, message: message)
    }
}
