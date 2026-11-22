import Testing
@testable import Sigils

@Test func steppingPausesAtRealInstructionsAndReportsSpans() {
    var session = ExecutionSession(source: "  1 2+\n\n  ->x x !print")
    #expect(session.nextLocation == SourceLocation(line: 1, column: 3))
    session.step()
    #expect(session.stack == [.number(1)])
    #expect(session.lastInstruction == SourceSpan(
        start: SourceLocation(line: 1, column: 3), end: SourceLocation(line: 1, column: 4)))
    session.step()
    session.step()
    #expect(session.stack == [.number(3)])
    #expect(session.nextLocation == SourceLocation(line: 3, column: 3))
    session.step()
    #expect(session.variables == ["x": .number(3)])
    session.step()
    #expect(session.step().output == "3\n")
    #expect(session.output == "3\n")
    #expect(session.isFinished)
    #expect(session.step().output == "")
}

@Test(arguments: [
    "10 20 30 ?@0 @2 ->@1 ->?@-1",
    "9 ->x x 1 + !print x",
    "1 0 / \"null\" + !print",
    "7 !print 1 + \"unreachable\"",
    "5 ?-> x",
    "1 2 + \"unfinished",
    "\"é中\" !print\n4 2 /",
])
func steppedExecutionMatchesOrdinaryExecution(source: String) {
    var interpreter = Interpreter()
    let ordinary = interpreter.evaluate(source)
    var session = ExecutionSession(source: source)
    var emitted = ""
    while !session.isFinished { emitted += session.step().output }
    #expect(session.stack == interpreter.stack)
    #expect(session.variables == interpreter.variables)
    #expect(session.error == ordinary.error)
    #expect(session.output == ordinary.output)
    #expect(emitted == ordinary.output)
}

@Test func steppingDoesNotPreparseOrRepeatFailedInstructions() {
    var session = ExecutionSession(source: "7 !print\n1\n+\n9")
    #expect(session.error == nil)
    session.step()
    #expect(session.step().output == "7\n")
    session.step()
    #expect(session.error == nil)
    session.step()
    #expect(session.error?.code == .stackUnderflow)
    #expect(session.error?.line == 3)
    #expect(session.stack == [.number(1)])
    #expect(session.isFinished)
    session.step()
    #expect(session.stack == [.number(1)])
    #expect(session.output == "7\n")
}

@Test func emptyAndWhitespaceOnlySessionsAreFinished() {
    for source in ["", " \n\t\r\n"] {
        var session = ExecutionSession(source: source)
        #expect(session.isFinished)
        #expect(session.step().error == nil)
        #expect(session.lastInstruction == nil)
    }
}
