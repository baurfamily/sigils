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

@Test(arguments: ["+ 4", "!print", "\"unfinished", "\"two\nlines\"", "1.", "-", "!unknown"])
func invalidProgramsFailWithoutChangingStack(source: String) throws {
    var interpreter = Interpreter()
    #expect(throws: LanguageError.self) { try interpreter.execute(source) }
    #expect(interpreter.stack.isEmpty)
}

@Test func failureRetainsSuccessfulInstructionsAndOperands() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("7")
    #expect(throws: LanguageError.self) {
        try interpreter.execute("!print 1 \"not a number\" +")
    }
    #expect(interpreter.stack == [.number(1), .string("not a number")])
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
func invalidArithmeticStopsExecution(source: String) throws {
    var interpreter = Interpreter()
    #expect(throws: LanguageError.self) { try interpreter.execute(source) }
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

@Test func sequentialStorageAndValueReads() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("10 3 ->right ->left left right -")
    #expect(interpreter.stack == [.number(7)])
    #expect(interpreter.variables == ["left": .number(10), "right": .number(3)])
}

@Test func bindingsPersistAndReadsAreSnapshots() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("5 ->x")
    _ = try interpreter.execute("x 8 ->x x")
    #expect(interpreter.stack == [.number(5), .number(8)])
    #expect(interpreter.variables["x"] == .number(8))
}

@Test func nullBindingIsNotUndefined() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("1 0 / ->x x")
    #expect(interpreter.variables["x"] == .null)
    #expect(interpreter.stack == [.null])
}

@Test func attachedStorageAndIdentifierRules() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("1->_value2 2->Value _value2 Value")
    #expect(interpreter.stack == [.number(1), .number(2)])
    #expect(interpreter.evaluate("value").error?.code == .undefinedVariable)
    #expect(interpreter.evaluate("3 ->2x").error?.code == .invalidDestination)
    #expect(interpreter.variables["Value"] == .number(2))
}

@Test func detachedStoragePreservesPrefixAndStopsBeforeReadingName() {
    var interpreter = Interpreter()
    let result = interpreter.evaluate("8 ->x\n5 -> x\nx")
    #expect(result.error?.code == .missingAttachedDestination)
    #expect(result.error?.line == 2)
    #expect(result.error?.column == 3)
    #expect(interpreter.variables["x"] == .number(8))
    #expect(interpreter.stack == [.number(5)])
}

@Test func storageUnderflowDoesNotReplaceABinding() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("7 ->x")
    #expect(interpreter.evaluate("->x").error?.code == .stackUnderflow)
    #expect(interpreter.variables["x"] == .number(7))
}

@Test func failurePreservesOutputAndDoesNotRunFollowingInstructions() {
    var interpreter = Interpreter()
    let result = interpreter.evaluate("\"before\" !print 5 ->x missing 99 ->x")
    #expect(result.output == "before\n")
    #expect(result.error?.code == .undefinedVariable)
    #expect(interpreter.variables["x"] == .number(5))
    #expect(interpreter.stack.isEmpty)
}

@Test func interactiveErrorsAreStructuredStackValues() throws {
    var interpreter = Interpreter()
    let result = interpreter.executeInteractive("5 -> x")
    let error = try #require(result.error)
    #expect(interpreter.stack == [.number(5), .error(error)])
    #expect(interpreter.stack.last?.description == "err:<missing-attached-destination, 1>")
    _ = try interpreter.execute("8 ->x x")
    #expect(interpreter.stack == [.number(5), .error(error), .number(8)])
}

@Test func failedArithmeticKeepsBothOperands() {
    var interpreter = Interpreter()
    let result = interpreter.evaluate("99 \"hello\" 4 + 8")
    #expect(result.error?.code == .typeError)
    #expect(interpreter.stack == [.number(99), .string("hello"), .number(4)])
}
