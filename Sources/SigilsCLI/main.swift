import Foundation
import Sigils
import SigilsSpecRunner
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WinSDK)
import WinSDK
#endif

struct CLIError: Error, CustomStringConvertible {
    let description: String
}

func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func writeOutput(_ message: String) {
    FileHandle.standardOutput.write(Data(message.utf8))
}

func runSource(_ source: String) throws {
    var interpreter = Interpreter()
    let output = try interpreter.execute(source)
    writeOutput(output)
}

func readStandardInput() throws -> String {
    let data = try FileHandle.standardInput.readToEnd() ?? Data()
    guard let source = String(data: data, encoding: .utf8) else {
        throw CLIError(description: "STDIN must be UTF-8")
    }
    return source
}

func runREPL() {
    var interpreter = Interpreter()
    writeOutput("Sigils REPL. Enter code; EOF exits.\n")
    while true {
        writeOutput("> ")
        guard let line = readLine() else {
            writeOutput("\n")
            return
        }
        do {
            writeOutput(try interpreter.execute(line))
            let values = interpreter.stack.map { value in
                if case .string(let text) = value { return String(reflecting: text) }
                return value.description
            }
            writeOutput("stack: [\(values.joined(separator: ", "))]\n")
        } catch {
            writeError(String(describing: error))
        }
    }
}

func standardInputIsTerminal() -> Bool {
    #if canImport(Darwin) || canImport(Glibc)
    return isatty(STDIN_FILENO) != 0
    #elseif canImport(WinSDK)
    var mode: DWORD = 0
    return GetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), &mode) != 0
    #else
    return false
    #endif
}

let usage = """
Usage:
  sigils repl                  Interactive, persistent stack
  sigils run <file|->           Execute a UTF-8 file or STDIN
  sigils <file>                 Execute a UTF-8 file
  sigils -                     Execute STDIN
  sigils spec [paths ...]       Run YAML cases (default: Spec/TestCases)
  sigils --help

Without arguments, start a REPL on a terminal, otherwise execute STDIN.
Spec paths may be files or directories; directories are searched recursively.
"""

func main() throws -> Bool {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        if standardInputIsTerminal() { runREPL() }
        else { try runSource(readStandardInput()) }
        return true
    }
    switch command {
    case "--help", "-h":
        guard arguments.count == 1 else { throw CLIError(description: usage) }
        writeOutput(usage + "\n")
    case "repl":
        guard arguments.count == 1 else { throw CLIError(description: usage) }
        runREPL()
    case "spec":
        let report = try SpecRunner.run(paths: arguments.count == 1
                                       ? ["Spec/TestCases"] : Array(arguments.dropFirst()))
        for result in report.results { writeOutput(result + "\n") }
        writeOutput("\(report.passed) passed, \(report.failed) failed\n")
        return report.failed == 0
    case "run":
        guard arguments.count == 2 else { throw CLIError(description: usage) }
        try runFile(arguments[1])
    default:
        guard arguments.count == 1 else { throw CLIError(description: usage) }
        try runFile(command)
    }
    return true
}

func runFile(_ path: String) throws {
    if path == "-" { try runSource(readStandardInput()) }
    else { try runSource(String(contentsOfFile: path, encoding: .utf8)) }
}

do {
    exit(try main() ? 0 : 1)
} catch {
    writeError(String(describing: error))
    exit(1)
}
