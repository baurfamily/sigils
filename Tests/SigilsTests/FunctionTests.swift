import Testing
@testable import Sigils

@Test func escapedCapturesSurviveSubmissionsAndInterpreterCopiesStayIndependent() throws {
    var original = Interpreter()
    _ = try original.execute("""
    {<0
      10 ->x
      {<0 :x 1 + ->:x :x }>1
    }>1 ->factory
    !factory ->counter
    """)
    var copy = original
    _ = try original.execute("!counter !counter")
    _ = try copy.execute("!counter")
    #expect(original.stack == [.number(11), .number(12)])
    #expect(copy.stack == [.number(11)])
    _ = try original.execute("!counter")
    #expect(original.stack.last == .number(13))
}

@Test func explicitOuterWritesSurvivePrivateFailureAndREPLRemainsUsable() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("10 ->x {:fail<1 20 ->:x !print + }>0")
    let result = interpreter.executeInteractive("99 8 !fail")
    #expect(result.error?.code == .stackUnderflow)
    #expect(result.output == "8\n")
    #expect(interpreter.variables["x"] == .number(20))
    #expect(interpreter.stack.count == 2)
    #expect(interpreter.stack.first == .number(99))
    guard case .error = interpreter.stack.last else {
        Issue.record("Interactive failure must append its structured error")
        return
    }
    _ = try interpreter.execute("x !print")
    #expect(interpreter.variables["x"] == .number(20))
}

@Test func functionFailureReportsTheOriginalBodyLocationAcrossSubmissions() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("""
    {:fail<0

      1 +
    }>0
    """)
    let result = interpreter.evaluate("99 !fail")
    #expect(result.error?.line == 3)
    #expect(result.error?.column == 5)
    #expect(interpreter.stack == [.number(99)])
}

@Test func returnedNamedFunctionValuesKeepTheirLexicalEnvironment() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("""
    {:factory<0
      4 ->x
      {:read<0 :x }>1
      read
    }>1
    !factory ->reader
    """)
    _ = try interpreter.execute("!reader")
    #expect(interpreter.stack == [.number(4)])
    #expect(interpreter.variables["read"] == nil)
}

@Test func callableAliasesShareIdentityButDifferentFactoriesDoNot() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("{<0 {<0 1 }>1 }>1 ->factory !factory ->first first ->alias !factory ->second")
    #expect(interpreter.variables["first"] == interpreter.variables["alias"])
    #expect(interpreter.variables["first"] != interpreter.variables["second"])
}

@Test(arguments: [
    "{:bad<0 1 }",
    "{:bad 1 }>1",
    "{:bad<-1 1 }>1",
    "{:bad?<1.5 1 }>1",
    "{:bad<999999999999999999999999 1 }>1",
    "{:bad?0 1 }>1",
    "{:bad<0 {<0 1 }>1",
])
func invalidDefinitionsDoNotInstallBindingsOrChangeTheStack(code: String) throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("99")
    let result = interpreter.evaluate(code)
    #expect(result.error?.code == .syntaxError)
    #expect(interpreter.variables["bad"] == nil)
    #expect(interpreter.stack == [.number(99)])
}

@Test func bracesInStringsDoNotEndFunctionBodies() throws {
    var interpreter = Interpreter()
    #expect(try interpreter.execute("{:braces<0 \"{hello}\" !print }>0 !braces") == "{hello}\n")
    #expect(interpreter.stack.isEmpty)
}

@Test func noncallableInvocationFailsBeforeConsumingInputs() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("1 ->notCallable 99")
    let result = interpreter.evaluate("!notCallable")
    #expect(result.error?.code == .typeError)
    #expect(interpreter.stack == [.number(99)])
}

@Test func explicitRecursiveCallFailsWithoutNativeRecursion() {
    var interpreter = Interpreter()
    let result = interpreter.evaluate("{:recursive<0 !:recursive }>0 !recursive")
    #expect(result.error?.code == .typeError)
    #expect(result.error?.message.contains("Recursive calls") == true)
}

@Test func immediateAnonymousCallsUseTheSameInputAndReturnRules() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("99 10 20 !{<2 + }>1")
    #expect(interpreter.stack == [.number(99), .number(30)])
}

@Test func steppedCallsMatchOrdinaryRunsWithoutRepeatingOutput() throws {
    let source = """
    1 ->x
    {:increment<0 :x 1 + ->:x :x !print }>0
    !increment !increment x
    """
    var session = ExecutionSession(source: source)
    var interpreter = Interpreter()
    let expectedOutput = try interpreter.execute(source)
    var output = ""
    while !session.isFinished { output += session.step().output }
    #expect(session.stack == interpreter.stack)
    #expect(session.variables["x"] == .number(3))
    #expect(output == expectedOutput)
    #expect(output == "2\n3\n")
}
