import Testing
@testable import StudioCore

@Test func lineSteppingUsesInstructionBoundariesAndSkipsBlankLines() {
    var run = DebugRun(source: "1 2 +\n\n3 *\n!print")
    #expect(run.result.stack.isEmpty)
    run.stepLine()
    #expect(run.result.stack.map(\.text) == ["3"])
    #expect(run.nextLocation?.line == 3)
    run.stepInstruction()
    #expect(run.result.stack.map(\.text) == ["3", "3"])
    run.stepLine()
    #expect(run.result.stack.map(\.text) == ["9"])
    run.stepLine()
    #expect(run.result.output == "9\n")
    #expect(run.isFinished)
}

@Test func runToCursorStopsBeforeTheTargetLineWithoutReplayingOutput() {
    var run = DebugRun(source: "7 !print\n\n1 2 +\n4 *")
    run.runToLine(3)
    #expect(run.result.output == "7\n")
    #expect(run.result.stack.isEmpty)
    #expect(run.nextLocation?.line == 3)
    run.runToLine(3)
    #expect(run.result.output == "7\n")
    run.stepLine()
    run.runToLine(10)
    #expect(run.result.stack.map(\.text) == ["12"])
    #expect(run.result.output == "7\n")
    #expect(run.isFinished)
}

@Test func lineSteppingStopsAtAnErrorWithoutExecutingLaterInstructions() {
    var run = DebugRun(source: "7 !print\n1 + 99\n100")
    run.runToLine(4)
    #expect(run.result.stack.map(\.text) == ["1"])
    #expect(run.result.output == "7\n")
    #expect(run.result.diagnostic?.hasPrefix("2:3: stack-underflow:") == true)
    run.stepLine()
    #expect(run.result.stack.map(\.text) == ["1"])
}

@Test func debuggingStepsOverCallsAndReportsBodyFailures() {
    var run = DebugRun(source: "{:f<0\n  1 +\n}>0\n99 !f\n100")
    run.stepInstruction()
    #expect(run.nextLocation?.line == 4)
    run.stepInstruction()
    #expect(run.result.stack.map(\.text) == ["99"])
    run.stepInstruction()
    #expect(run.isFinished)
    #expect(run.failureLocation?.line == 2)
    #expect(run.failureLocation?.column == 5)
    #expect(run.result.stack.map(\.text) == ["99"])
}
