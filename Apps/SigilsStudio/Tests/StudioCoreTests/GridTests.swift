import MessagePack
import Testing
@testable import StudioCore

private func event(_ name: String, _ args: [MessagePackValue]...) -> MessagePackValue {
    .array([.string(name)] + args.map(MessagePackValue.array))
}

@Test func gridLinesRepeatsHighlightsWideCellsAndFlush() throws {
    var grid = EditorGrid()
    var frames: [EditorGrid] = []
    try grid.apply([
        event("grid_resize", [.int(1), .int(5), .int(2)]),
        event("hl_attr_define", [.int(3), .map([.string("foreground"): .int(0xFF0000), .string("bold"): .bool(true)])]),
        event("grid_line", [.int(1), .int(0), .int(0), .array([
            .array([.string("ignored"), .int(3), .int(0)]),
            .array([.string("a"), .int(3), .int(2)]),
            .array([.string("b")]),
            .array([.string("中")]),
            .array([.string("")]),
        ])]),
        event("grid_cursor_goto", [.int(1), .int(0), .int(3)]),
        event("mode_change", [.string("insert"), .int(2)]),
    ]) { frames.append($0) }
    #expect(frames.isEmpty)
    try grid.apply([event("flush", [])]) { frames.append($0) }
    let frame = try #require(frames.first)
    #expect(frame.cells[0].map(\.text) == ["a", "a", "b", "中", ""])
    #expect(frame.cells[0].allSatisfy { $0.highlight == 3 })
    #expect(frame.highlights[3]?.foreground == 0xFF0000)
    #expect(frame.highlights[3]?.bold == true)
    #expect(frame.cursorColumn == 3)
    #expect(frame.mode == "insert")
}

@Test func scrollingOnlyChangesItsRegion() throws {
    var grid = EditorGrid()
    try grid.apply([
        event("grid_resize", [.int(1), .int(3), .int(3)]),
        event("grid_line", [.int(1), .int(0), .int(0), .array(["a", "b", "c"].map { .array([.string($0)]) })]),
        event("grid_line", [.int(1), .int(1), .int(0), .array(["d", "e", "f"].map { .array([.string($0)]) })]),
        event("grid_line", [.int(1), .int(2), .int(0), .array(["g", "h", "i"].map { .array([.string($0)]) })]),
        event("grid_scroll", [.int(1), .int(0), .int(3), .int(1), .int(3), .int(1), .int(0)]),
    ]) { _ in }
    #expect(grid.cells.map { $0.map(\.text) } == [["a", "e", "f"], ["d", "h", "i"], ["g", " ", " "]])
}

@Test func invalidRedrawsFailWithoutPublishingAFrame() throws {
    var grid = EditorGrid()
    var frames = 0
    #expect(throws: StudioError.self) {
        try grid.apply([
            event("grid_resize", [.int(1), .int(1), .int(1)]),
            event("grid_line", [.int(1), .int(0), .int(0), .array([.array([.string("x"), .int(0), .int(2)])])]),
            event("flush", []),
        ]) { _ in frames += 1 }
    }
    #expect(frames == 0)
}

@Test func futureUIEventsAreCompatible() throws {
    var grid = EditorGrid()
    var frames = 0
    try grid.apply([event("future_event", [.string("extension")]), event("flush", [])]) { _ in frames += 1 }
    #expect(frames == 1)
}
