import Foundation
import Testing
import SigilsSpecRunner

@Test func independentDocumentsAndEmptyTrailingDocument() throws {
    let report = try SpecRunner.evaluate(yaml: """
    ---
    name: first
    code: 1 4 +
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

@Test func nullStackEntryIsDistinctFromAnEmptyStack() throws {
    let report = try SpecRunner.evaluate(yaml: """
    name: null result
    code: 1 0 /
    output:
    stack: [null]
    ---
    name: consumed null
    code: 1 0 / !print
    output:
    stack:
    """)
    #expect(report.passed == 2)
    #expect(report.failed == 0)
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

@Test(arguments: ["low", "medium", "high"])
func confidenceControlsExecution(confidence: String) throws {
    let report = try SpecRunner.evaluate(yaml: """
    name: matching case
    confidence: \(confidence)
    code: 1 2 +
    output:
    stack: [3]
    ---
    name: mismatching case
    confidence: \(confidence)
    code: 1 2 +
    output:
    stack: [4]
    """)
    if confidence == "low" {
        #expect(report.passed == 0)
        #expect(report.failed == 0)
        #expect(report.skipped == 2)
        #expect(report.results.allSatisfy { $0.hasPrefix("SKIP ") })
    } else {
        #expect(report.passed == 1)
        #expect(report.failed == 1)
        #expect(report.skipped == 0)
        #expect(report.results[1].contains("stack expected"))
    }
}

@Test(arguments: ["unknown", "High", "null", "1", "[high]"])
func invalidConfidenceMetadataFails(confidence: String) throws {
    let report = try SpecRunner.evaluate(yaml: """
    name: invalid confidence
    confidence: \(confidence)
    code: ""
    output:
    stack: []
    """)
    #expect(report.failed == 1)
    #expect(report.results[0].contains("confidence must be low, medium, or high"))
}

@Test func errorAssertionsCheckCategoryAndOptionalPrefixState() throws {
    let report = try SpecRunner.evaluate(yaml: """
    name: expected failure with state
    code: |
      8 ->x
      5 -> x
    error: missing-attached-destination
    output:
    stack: [5]
    ---
    name: expected failure
    code: missing
    error: undefined-variable
    ---
    name: wrong error
    code: missing
    error: stack-underflow
    ---
    name: absent error
    code: 5
    error: stack-underflow
    ---
    name: unexpected error
    code: missing
    output:
    stack: []
    """)
    #expect(report.passed == 2)
    #expect(report.failed == 3)
}

@Test(arguments: ["null", "1", "unknown", "[undefined-variable]"])
func invalidErrorCategoriesFail(error: String) throws {
    let report = try SpecRunner.evaluate(yaml: """
    name: invalid error
    code: missing
    error: \(error)
    """)
    #expect(report.failed == 1)
    #expect(report.results[0].contains("error must be a known language error category"))
}

@Test func errorAssertionsStillCheckOutputAndStack() throws {
    let report = try SpecRunner.evaluate(yaml: """
    name: wrong state
    code: '"before" !print 5 -> x'
    error: missing-attached-destination
    output: wrong
    stack: [9]
    """)
    #expect(report.failed == 1)
    #expect(report.results[0].contains("output expected"))
    #expect(report.results[0].contains("stack expected"))
}

@Test func lowConfidenceCaseDoesNotExecuteUnsupportedSyntax() throws {
    let report = try SpecRunner.evaluate(yaml: """
    name: future syntax
    confidence: low
    code: "not-implemented"
    output: future output
    stack: [99]
    """)
    #expect(report.passed == 0)
    #expect(report.failed == 0)
    #expect(report.skipped == 1)
}

@Test func lowConfidenceStillRequiresValidCaseSchema() throws {
    let report = try SpecRunner.evaluate(yaml: """
    name: malformed draft
    confidence: low
    code: ""
    output:
    stack: []
    unexpected: typo
    """)
    #expect(report.failed == 1)
    #expect(report.skipped == 0)
}

@Test func skippedCountsAggregateAcrossFiles() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sigils-confidence-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer {
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Failed to remove test directory: \(error)") }
    }
    let yaml = """
    name: deferred case
    confidence: low
    code: unknown
    output:
    stack: []
    """
    for name in ["first.yml", "second.yaml"] {
        try yaml.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    let report = try SpecRunner.run(paths: [directory.path])
    #expect(report.passed == 0)
    #expect(report.failed == 0)
    #expect(report.skipped == 2)
}
