import Testing
@testable import Sigils

@Test func scalarsAndPrint() throws {
    var interpreter = Interpreter()
    let output = try interpreter.execute("5\n12.2 -8 0.1 \"hello\" !print")
    #expect(output == "hello\n")
    #expect(interpreter.stack == [.number(5), .number(12.2), .number(-8), .number(0.1)])
}

@Test func additionConsumesOnlyTopTwoValues() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("9 1 4+ -2.5+")
    #expect(interpreter.stack == [.number(9), .number(2.5)])
}

@Test func interactiveExecutionsRetainStack() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("1")
    _ = try interpreter.execute("4")
    _ = try interpreter.execute("+")
    #expect(try interpreter.execute("!print") == "5\n")
    #expect(interpreter.stack.isEmpty)
}

@Test(arguments: ["+ 4", "!print", "\"hello\" 4 +", "1 \"hello\" +",
                  "1 +", "\"unfinished", "\"two\nlines\"", "1.", "-", "!unknown"])
func invalidProgramsFailWithoutChangingStack(source: String) throws {
    var interpreter = Interpreter()
    #expect(throws: LanguageError.self) { try interpreter.execute(source) }
    #expect(interpreter.stack.isEmpty)
}

@Test func failureRestoresExistingStack() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("7")
    #expect(throws: LanguageError.self) {
        try interpreter.execute("!print 1 \"not a number\" +")
    }
    #expect(interpreter.stack == [.number(7)])
}

@Test(arguments: [
    ("9 4 1 -", 3.0),
    ("9 2 3 *", 6.0),
    ("9 8 2 /", 4.0),
    ("9 5 2 /", 2.5),
    ("9 1 3 /", 1.0 / 3.0),
    ("9 -8 2 /", -4.0),
    ("9 4 -1 -", 5.0),
])
func arithmeticPreservesDeeperStack(source: String, result: Double) throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute(source)
    #expect(interpreter.stack == [.number(9), .number(result)])
}

@Test func concatenationProducesAStackValueWithoutOutput() throws {
    var interpreter = Interpreter()
    #expect(try interpreter.execute("\"hello\" \" \" + \"world\" +") == "")
    #expect(interpreter.stack == [.string("hello world")])
}

@Test(arguments: ["1 0 /", "0 0 /", "1 -0 /", "1 0 / 2 +", "1 0 / 2 -",
                  "1 0 / 2 *", "1 0 / 2 /",
                  "2 1 0 / +", "2 1 0 / -", "2 1 0 / *", "2 1 0 / /",
                  "1 0 / 2 0 / +"])
func zeroDivisionAndNumericNullPropagation(source: String) throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute(source)
    #expect(interpreter.stack == [.null])
}

@Test func nullPrintingConsumesWithoutOutput() throws {
    var interpreter = Interpreter()
    #expect(try interpreter.execute("7 1 0 / !print") == "")
    #expect(interpreter.stack == [.number(7)])
}

@Test(arguments: ["1 0 / \"hello\" + \" world\" +",
                  "\"hello\" 1 0 / + \" world\" +"])
func nullConcatenationCoercesToEmptyText(source: String) throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute(source)
    #expect(interpreter.stack == [.string("hello world")])
}

@Test(arguments: ["\"text\" 1 -", "\"text\" 2 *", "\"text\" 2 /", "1 0 / \"text\" *",
                  "* 2", "/ 2", "4 -", "4 *", "4 /", "1 + 2", "1 * 2", "1 / 2", "1 - 2"])
func invalidArithmeticFailsWithoutChangingStack(source: String) throws {
    var interpreter = Interpreter()
    #expect(throws: LanguageError.self) { try interpreter.execute(source) }
    #expect(interpreter.stack.isEmpty)
}

@Test func operatorsNeverConsumeFollowingValues() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("1 2 + 4")
    #expect(interpreter.stack == [.number(3), .number(4)])
}

@Test func signedLiteralsDoNotBecomeSubtraction() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("4 -1")
    #expect(interpreter.stack == [.number(4), .number(-1)])
}

@Test func underflowPreservesExistingStackAcrossExecutions() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("7")
    #expect(throws: LanguageError.self) { try interpreter.execute("+ 4") }
    #expect(interpreter.stack == [.number(7)])
}
