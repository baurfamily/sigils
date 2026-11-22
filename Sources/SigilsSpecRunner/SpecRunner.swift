import Foundation
import Sigils
import Yams

public struct SpecReport {
    public var passed = 0
    public var failed = 0
    public var results: [String] = []
}

public struct SpecError: Error, CustomStringConvertible {
    public let description: String
}

public enum SpecRunner {
    public static func run(paths: [String]) throws -> SpecReport {
        let files = try discover(paths: paths)
        guard !files.isEmpty else { throw SpecError(description: "No YAML spec files found") }
        var report = SpecReport()
        for file in files {
            do {
                let yaml = try String(contentsOfFile: file, encoding: .utf8)
                let fileReport = try evaluate(yaml: yaml, label: file)
                report.passed += fileReport.passed
                report.failed += fileReport.failed
                report.results += fileReport.results
            } catch {
                report.failed += 1
                report.results.append("FAIL \(file): \(error)")
            }
        }
        return report
    }

    public static func evaluate(yaml: String, label: String = "<yaml>") throws -> SpecReport {
        var documents = try Yams.compose_all(yaml: yaml)
        var report = SpecReport()
        var index = 0
        var cases = 0
        while let node = documents.next() {
            index += 1
            // A trailing YAML document separator creates an empty document.
            if node.tag == Tag(.null), node.scalar?.string.isEmpty == true { continue }
            cases += 1
            var location = "\(label):document \(index)"
            do {
                let spec = try decode(node)
                location += " (\(spec.name))"
                var interpreter = Interpreter()
                let execution = interpreter.evaluate(spec.code)
                let output = execution.output
                var differences: [String] = []
                if execution.error?.code != spec.error {
                    differences.append(
                        "error expected \(spec.error?.rawValue ?? "none"), got \(execution.error?.description ?? "none")"
                    )
                }
                let actualOutput = spec.exactOutput ? output : removingFinalNewline(output)
                if let expected = spec.output {
                    let expectedOutput = spec.exactOutput ? expected : removingFinalNewline(expected)
                    if actualOutput != expectedOutput {
                        differences.append(
                            "output expected \(String(reflecting: expected)), got \(String(reflecting: output))"
                        )
                    }
                }
                if let expectedStack = spec.stack, interpreter.stack != expectedStack {
                    differences.append(
                        "stack expected \(describe(expectedStack)), got \(describe(interpreter.stack))"
                    )
                }
                if differences.isEmpty {
                    report.passed += 1
                    report.results.append("PASS \(location)")
                } else {
                    report.failed += 1
                    report.results.append("FAIL \(location): \(differences.joined(separator: "; "))")
                }
            } catch {
                report.failed += 1
                report.results.append("FAIL \(location): \(error)")
            }
        }
        if let error = documents.error { throw error }
        guard cases > 0 else { throw SpecError(description: "\(label): No spec cases found") }
        return report
    }

    private struct Case {
        let name: String
        let code: String
        let output: String?
        let exactOutput: Bool
        let stack: [Value]?
        let error: ErrorCode?
    }

    private static func decode(_ node: Node) throws -> Case {
        guard let mapping = node.mapping else { throw invalid("Case must be a mapping") }
        let allowed: Set<String> = ["name", "code", "output", "stack", "commentary", "confidence", "error"]
        var seen: Set<String> = []
        for pair in mapping {
            guard pair.key.tag == Tag(.str), let key = pair.key.string, allowed.contains(key) else {
                throw invalid("Unknown case field \(pair.key)")
            }
            guard seen.insert(key).inserted else { throw invalid("Duplicate field \(key)") }
        }
        if let confidence = node["confidence"] {
            guard confidence.tag == Tag(.str), let text = confidence.string,
                  ["low", "medium", "high"].contains(text) else {
                throw invalid("confidence must be low, medium, or high")
            }
        }
        guard let name = node["name"], name.tag == Tag(.str),
              let nameText = name.string, !nameText.isEmpty else {
            throw invalid("name must be a nonempty string")
        }
        guard let code = node["code"], code.tag == Tag(.str), let source = code.string else {
            throw invalid("code must be a string")
        }
        let expectedError: ErrorCode?
        if let error = node["error"] {
            guard error.tag == Tag(.str), let text = error.string,
                  let code = ErrorCode(rawValue: text) else {
                throw invalid("error must be a known language error category")
            }
            expectedError = code
        } else { expectedError = nil }
        let outputText: String?
        if let output = node["output"] {
            if output.tag == Tag(.null) { outputText = "" }
            else if output.tag == Tag(.str), let text = output.string { outputText = text }
            else { throw invalid("output must be a string or null") }
        } else if expectedError != nil { outputText = nil }
        else { throw invalid("Missing output") }
        let stack: [Value]?
        if let stackNode = node["stack"] {
            if stackNode.tag == Tag(.null) { stack = [] }
            else if let sequence = stackNode.sequence { stack = try sequence.map(value) }
            else { throw invalid("stack must be a sequence or null") }
        } else if expectedError != nil { stack = nil }
        else { throw invalid("Missing stack") }
        let style = node["output"]?.scalar?.style
        return Case(
            name: nameText, code: source, output: outputText,
            exactOutput: style == .literal || style == .folded, stack: stack, error: expectedError
        )
    }

    private static func value(_ node: Node) throws -> Value {
        if node.tag == Tag(.null) { return .null }
        if node.tag == Tag(.str), let text = node.string { return .string(text) }
        if node.tag == Tag(.int) || node.tag == Tag(.float),
           let number = node.float, number.isFinite {
            return .number(number)
        }
        throw invalid("Expected stack values must be finite numbers, strings, or null")
    }

    private static func invalid(_ message: String) -> SpecError {
        SpecError(description: message)
    }

    private static func removingFinalNewline(_ text: String) -> String {
        text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    private static func describe(_ stack: [Value]) -> String {
        let elements = stack.map { value in
            if case .string(let text) = value { return String(reflecting: text) }
            return value.description
        }
        return "[\(elements.joined(separator: ", "))]"
    }

    private static func discover(paths: [String]) throws -> [String] {
        let manager = FileManager.default
        var files: Set<String> = []
        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            var directory: ObjCBool = false
            guard manager.fileExists(atPath: url.path, isDirectory: &directory) else {
                throw invalid("Spec path does not exist: \(path)")
            }
            if directory.boolValue {
                var enumerationError: Error?
                guard let enumerator = manager.enumerator(
                    at: url, includingPropertiesForKeys: [.isRegularFileKey],
                    errorHandler: { _, error in
                        enumerationError = error
                        return false
                    }
                ) else { throw invalid("Cannot read spec directory: \(path)") }
                for case let file as URL in enumerator where isYAML(file) {
                    if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                        files.insert(file.standardizedFileURL.path)
                    }
                }
                if let error = enumerationError { throw error }
            } else {
                guard isYAML(url) else { throw invalid("Not a YAML file: \(path)") }
                files.insert(url.path)
            }
        }
        return files.sorted()
    }

    private static func isYAML(_ url: URL) -> Bool {
        ["yaml", "yml"].contains(url.pathExtension.lowercased())
    }
}
