import Sigils

public struct StackEntry: Sendable {
    public let index: Int
    public let kind: String
    public let text: String
}

public struct ScriptRun: Sendable {
    public let stack: [StackEntry]
    public let output: String
    public let diagnostic: String?

    public static func execute(_ source: String) -> ScriptRun {
        var interpreter = Interpreter()
        let result = interpreter.evaluate(source)
        return snapshot(stack: interpreter.stack, output: result.output, diagnostic: result.error?.description)
    }

    public static func snapshot(stack: [Value], output: String, diagnostic: String?) -> ScriptRun {
        let entries = stack.reversed().enumerated().map { index, value in
            let kind: String
            let text: String
            switch value {
            case .number:
                kind = "number"
                text = value.description
            case .string(let string):
                kind = "string"
                text = String(reflecting: string)
            case .null:
                kind = "null"
                text = "null"
            case .error:
                kind = "error"
                text = value.description
            case .function:
                kind = "function"
                text = value.description
            }
            return StackEntry(index: index, kind: kind, text: text)
        }
        return ScriptRun(stack: entries, output: output, diagnostic: diagnostic)
    }
}
