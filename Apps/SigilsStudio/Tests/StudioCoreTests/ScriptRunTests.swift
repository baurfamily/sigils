import Testing
@testable import StudioCore

@Test func scriptRunsAreFreshAndStackIsTopFirst() {
    let first = ScriptRun.execute("10 ->x 20 30")
    #expect(first.stack.map(\.text) == ["30", "20"])
    #expect(first.stack.map(\.index) == [0, 1])
    let next = ScriptRun.execute("x")
    #expect(next.stack.isEmpty)
    #expect(next.diagnostic?.contains("undefined-variable") == true)
}

@Test func scriptFailureKeepsPrefixOutputAndNoREPLErrorValue() {
    let run = ScriptRun.execute("7\n!print\n1\n+")
    #expect(run.output == "7\n")
    #expect(run.stack.map(\.text) == ["1"])
    #expect(run.diagnostic?.hasPrefix("4:1: stack-underflow:") == true)
}

@Test func stringsAndNullRemainVisuallyDistinct() {
    let run = ScriptRun.execute("\"null\" 1 0 /")
    #expect(run.stack.map(\.kind) == ["null", "string"])
    #expect(run.stack.map(\.text) == ["null", "\"null\""])
}

@Test func functionValuesHaveTheirOwnStackDisplayType() {
    let run = ScriptRun.execute("{<0 10 }>1")
    #expect(run.stack.map(\.kind) == ["function"])
    #expect(run.stack.map(\.text) == ["<function>"])
    #expect(run.diagnostic == nil)
}
