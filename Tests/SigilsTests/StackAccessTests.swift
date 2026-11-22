import Testing
@testable import Sigils

@Test func positiveAndNegativeIndicesAddressTheSameEntries() throws {
    for count in 1...6 {
        let values = (1...count).map { Value.number(Double($0)) }
        let source = values.map(\.description).joined(separator: " ")
        for position in values.indices {
            let indices = [count - 1 - position, -position - 1]
            for index in indices {
                var moved = Interpreter()
                _ = try moved.execute("\(source) @\(index)")
                var expectedMove = values
                expectedMove.append(expectedMove.remove(at: position))
                #expect(moved.stack == expectedMove)

                var copied = Interpreter()
                _ = try copied.execute("\(source) ?@\(index)")
                #expect(copied.stack == values + [values[position]])

                var replaced = Interpreter()
                _ = try replaced.execute("\(source) ->@\(index)")
                var expectedReplacement = values
                expectedReplacement[position] = values[count - 1]
                if position != count - 1 { expectedReplacement.removeLast() }
                #expect(replaced.stack == expectedReplacement)

                var preserved = Interpreter()
                _ = try preserved.execute("\(source) ?->@\(index)")
                var expectedPreserved = values
                expectedPreserved[position] = values[count - 1]
                #expect(preserved.stack == expectedPreserved)
            }
        }
    }
}

@Test(arguments: [
    ("->?@0", [10.0, 20, 30]),
    ("->?@1", [10.0, 20, 30]),
    ("->?@2", [10.0, 30, 20]),
    ("->?@3", [30.0, 10, 20]),
    ("->?@-1", [30.0, 10, 20]),
    ("->?@-2", [10.0, 30, 20]),
    ("->?@-3", [10.0, 20, 30]),
    ("->?@-4", [10.0, 20, 30]),
])
func provisionalInsertionUsesOriginalStackGaps(operation: String, expected: [Double]) throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("10 20 30 \(operation)")
    #expect(interpreter.stack == expected.map(Value.number))
}

@Test(arguments: [0, 1, -1, -2])
func insertionWithSingleValuePreservesThatValue(index: Int) throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("5 ->?@\(index)")
    #expect(interpreter.stack == [.number(5)])
}

@Test func insertionReadsVariableGapWithoutConsumingBinding() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("3 ->gap 10 20 30 ->?@gap")
    #expect(interpreter.stack == [.number(30), .number(10), .number(20)])
    #expect(interpreter.variables["gap"] == .number(3))
}

@Test func insertionPreservesNullDestinationValues() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("10 5 0 / 30 ->?@2")
    #expect(interpreter.stack == [.number(10), .number(30), .null])
}

@Test func insertionCanMoveANullSource() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("10 20 5 0 / ->?@-1")
    #expect(interpreter.stack == [.null, .number(10), .number(20)])
}

@Test(arguments: ["@3", "?@-4", "->@3", "?->@-4", "->?@4", "->?@-5",
                  "@9223372036854775808", "->?@-9223372036854775808"])
func outOfBoundsAccessPreservesTheEntireStack(operation: String) throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("10 20 30")
    let result = interpreter.evaluate(operation)
    #expect(result.error?.code == .stackIndexOutOfBounds)
    #expect(interpreter.stack == [.number(10), .number(20), .number(30)])
}

@Test(arguments: ["@0.5", "?@-0.5", "->@1.5", "?->@0.5", "->?@0.5"])
func fractionalIndicesNeverConsumeOrReplaceValues(operation: String) throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("10 20 30")
    #expect(interpreter.evaluate(operation).error?.code == .invalidStackIndex)
    #expect(interpreter.stack == [.number(10), .number(20), .number(30)])
}

@Test(arguments: ["@", "?@", "@ 1", "->@", "-> @1", "->?@", "->? @1", "?->?@1"])
func malformedIndexOperationsPreserveState(operation: String) throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("10 20 30")
    #expect(interpreter.evaluate(operation).error != nil)
    #expect(interpreter.stack == [.number(10), .number(20), .number(30)])
    #expect(interpreter.variables.isEmpty)
}

@Test(arguments: ["->@0", "?->@0", "->?@0"])
func emptyIndexedWritesHaveNoSource(operation: String) {
    var interpreter = Interpreter()
    #expect(interpreter.evaluate(operation).error?.code == .stackUnderflow)
    #expect(interpreter.stack.isEmpty)
}

@Test func indexErrorsInTheREPLCarryTheInstructionLocation() throws {
    var interpreter = Interpreter()
    _ = try interpreter.execute("10 20 30")
    let result = interpreter.executeInteractive("1 ->depth\n?@9")
    let error = try #require(result.error)
    #expect(error.code == .stackIndexOutOfBounds)
    #expect(error.line == 2)
    #expect(error.column == 1)
    #expect(interpreter.stack == [.number(10), .number(20), .number(30), .error(error)])
    #expect(interpreter.variables["depth"] == .number(1))
}

@Test func structuredErrorsCanBeCopiedAndInsertedAsValues() throws {
    var interpreter = Interpreter()
    let failure = try #require(interpreter.executeInteractive("missing").error)
    _ = try interpreter.execute("?@0 5 ->?@-1")
    #expect(interpreter.stack == [.number(5), .error(failure), .error(failure)])
}
