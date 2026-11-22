import Testing
@testable import Sigils

@Test func scalarsAndPrint() throws {
    var interpreter = Interpreter()
    let output = try interpreter.execute("5\n12.2 -8 0.1 \"hello\" !print")
    #expect(output == "hello\n")
    #expect(interpreter.stack == [.number(5), .number(12.2), .number(-8), .number(0.1)])
}

@Test func additionConsumesOnlyTopAndRightOperand() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("9 1+4 + -2.5")
    #expect(interpreter.stack == [.number(9), .number(2.5)])
}

@Test func interactiveExecutionsRetainStack() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("1")
    _ = try interpreter.execute("+ 4")
    #expect(try interpreter.execute("!print") == "5\n")
    #expect(interpreter.stack.isEmpty)
}

@Test(arguments: ["+ 4", "!print", "\"hello\" + 4", "1 + \"hello\"",
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
        try interpreter.execute("!print 1 + \"not a number\"")
    }
    #expect(interpreter.stack == [.number(7)])
}
