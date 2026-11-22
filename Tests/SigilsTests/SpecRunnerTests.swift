import Foundation
import Testing
import SigilsSpecRunner

@Test func independentDocumentsAndEmptyTrailingDocument() throws {
    let report = try SpecRunner.evaluate(yaml: """
    ---
    name: first
    code: 1 + 4
    output:
    stack: [5]
    ---
    name: second
    code: '"hello" !print'
    output: hello
    stack:
    ---
    """)
    #expect(report.passed == 2)
    #expect(report.failed == 0)
}

@Test func stackComparisonPreservesTypesAndOrder() throws {
    let report = try SpecRunner.evaluate(yaml: """
    name: wrong stack
    code: '1 "2"'
    output:
    stack: ["1", 2]
    """)
    #expect(report.failed == 1)
    #expect(report.results[0].contains("stack expected"))
}

@Test func blockOutputIsExact() throws {
    let report = try SpecRunner.evaluate(yaml: """
    name: missing newline
    code: '"hello" !print'
    output: |-
      hello
    stack: []
    """)
    #expect(report.failed == 1)
}

@Test(arguments: ["stack: [true]", "stack: []\nfuture: ignored"])
func invalidSchemaFails(fields: String) throws {
    let report = try SpecRunner.evaluate(yaml: """
    name: invalid schema
    code: ""
    output:
    \(fields)
    """)
    #expect(report.failed == 1)
}

@Test(arguments: [
    "name: duplicate\ncode: \"\"\noutput:\nstack: []\nstack: [1]",
    "name: valid\ncode: \"\"\noutput:\nstack: []\n---\nstack: [",
])
func invalidYAMLCannotSilentlyPass(yaml: String) {
    #expect(throws: (any Error).self) {
        try SpecRunner.evaluate(yaml: yaml)
    }
}

@Test func repositorySpecs() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let report = try SpecRunner.run(paths: [root.appendingPathComponent("Spec/TestCases").path])
    #expect(report.failed == 0, "\(report.results)")
    #expect(report.passed > 0)
}
