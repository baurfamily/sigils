public enum Value: Equatable, Sendable, CustomStringConvertible {
    case number(Double)
    case string(String)

    public var description: String {
        switch self {
        case .number(let number):
            let text = String(number)
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        case .string(let string):
            return string
        }
    }
}

public struct LanguageError: Error, CustomStringConvertible {
    public let description: String
}

public struct Interpreter {
    public private(set) var stack: [Value] = []

    public init() {}

    /// Successful executions retain their stack; failed executions leave it unchanged.
    public mutating func execute(_ source: String) throws -> String {
        var parser = Parser(source: source, stack: stack)
        let output = try parser.run()
        stack = parser.stack
        return output
    }
}

private struct Parser {
    let characters: [Character]
    var position = 0
    var stack: [Value]

    init(source: String, stack: [Value]) {
        characters = Array(source)
        self.stack = stack
    }

    mutating func run() throws -> String {
        var output = ""
        while true {
            skipWhitespace()
            guard position < characters.count else { return output }
            switch characters[position] {
            case "+":
                position += 1
                guard let left = stack.last else {
                    throw error("Addition needs a value on the stack")
                }
                guard case .number(let lhs) = left else {
                    throw error("Addition requires numbers")
                }
                skipWhitespace()
                let right = try scalar()
                guard case .number(let rhs) = right else {
                    throw error("Addition requires numbers")
                }
                let result = lhs + rhs
                guard result.isFinite else { throw error("Numeric overflow") }
                stack.removeLast()
                stack.append(.number(result))
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
                    throw error("Unknown function !\(name)")
                }
                guard let value = stack.popLast() else {
                    throw error("!print needs a value on the stack")
                }
                output += value.description + "\n"
            default:
                stack.append(try scalar())
            }
        }
    }

    mutating func scalar() throws -> Value {
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

    func error(_ message: String) -> LanguageError {
        let prefix = characters[..<position]
        let line = prefix.filter(\.isNewline).count + 1
        let lastNewline = prefix.lastIndex(where: \.isNewline)
        let column = position - (lastNewline.map { $0 + 1 } ?? 0) + 1
        return LanguageError(description: "\(line):\(column): \(message)")
    }
}
