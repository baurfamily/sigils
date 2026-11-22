import MessagePack

public struct EditorCell: Equatable, Sendable {
    public var text = " "
    public var highlight = 0
}

public struct EditorHighlight: Sendable {
    public var foreground: Int?
    public var background: Int?
    public var bold = false
    public var italic = false
    public var reverse = false
    public var underline = false
}

public struct EditorGrid: Sendable {
    public private(set) var cells: [[EditorCell]] = []
    public private(set) var cursorRow = 0
    public private(set) var cursorColumn = 0
    public private(set) var highlights: [Int: EditorHighlight] = [:]
    public private(set) var foreground: Int?
    public private(set) var background: Int?
    public private(set) var mode = "normal"

    public var width: Int { cells.first?.count ?? 0 }
    public var height: Int { cells.count }

    public init() {}

    mutating func apply(_ updates: [MessagePackValue], flush: (EditorGrid) -> Void) throws {
        for update in updates {
            let event = try update.elements()
            guard let first = event.first else { throw StudioError.protocolError("Empty redraw event") }
            let name = try first.text()
            for arguments in event.dropFirst() {
                let args = try arguments.elements()
                if name == "flush" {
                    flush(self)
                    continue
                }
                switch name {
                case "grid_resize":
                    try require(args, 3)
                    guard try args[0].integer() == 1 else { throw unsupportedGrid() }
                    let width = try args[1].integer()
                    let height = try args[2].integer()
                    guard width > 0, height > 0, width <= 1000, height <= 1000 else {
                        throw StudioError.protocolError("Invalid grid size \(width) x \(height)")
                    }
                    cells = Array(repeating: Array(repeating: EditorCell(), count: width), count: height)
                    cursorRow = 0
                    cursorColumn = 0
                case "grid_clear":
                    try require(args, 1)
                    guard try args[0].integer() == 1 else { throw unsupportedGrid() }
                    cells = Array(repeating: Array(repeating: EditorCell(), count: width), count: height)
                case "grid_line":
                    try require(args, 4)
                    guard try args[0].integer() == 1 else { throw unsupportedGrid() }
                    let row = try args[1].integer()
                    var column = try args[2].integer()
                    guard cells.indices.contains(row), column >= 0, column < width else {
                        throw StudioError.protocolError("Grid line is outside the viewport")
                    }
                    var highlight = 0
                    for item in try args[3].elements() {
                        let cell = try item.elements()
                        try require(cell, 1)
                        let text = try cell[0].text()
                        if cell.count > 1 { highlight = try cell[1].integer() }
                        let count = cell.count > 2 ? try cell[2].integer() : 1
                        guard count >= 0, count <= width - column else {
                            throw StudioError.protocolError("Cell repeat \(count) at \(row):\(column) exceeds grid width \(width)")
                        }
                        for _ in 0..<count {
                            cells[row][column] = EditorCell(text: text, highlight: highlight)
                            column += 1
                        }
                    }
                case "grid_cursor_goto":
                    try require(args, 3)
                    guard try args[0].integer() == 1 else { throw unsupportedGrid() }
                    let row = try args[1].integer()
                    let column = try args[2].integer()
                    guard cells.indices.contains(row), column >= 0, column < width else {
                        throw StudioError.protocolError("Cursor is outside the viewport")
                    }
                    cursorRow = row
                    cursorColumn = column
                case "grid_scroll":
                    try require(args, 7)
                    guard try args[0].integer() == 1 else { throw unsupportedGrid() }
                    let top = try args[1].integer()
                    let bottom = try args[2].integer()
                    let left = try args[3].integer()
                    let right = try args[4].integer()
                    let rows = try args[5].integer()
                    let columns = try args[6].integer()
                    guard top >= 0, top <= bottom, bottom <= height,
                          left >= 0, left <= right, right <= width,
                          rows >= -height, rows <= height, columns >= -width, columns <= width else {
                        throw StudioError.protocolError("Invalid scroll region")
                    }
                    let previous = cells
                    for row in top..<bottom {
                        for column in left..<right {
                            let sourceRow = row + rows
                            let sourceColumn = column + columns
                            cells[row][column] = (top..<bottom).contains(sourceRow)
                                && (left..<right).contains(sourceColumn)
                                ? previous[sourceRow][sourceColumn] : EditorCell()
                        }
                    }
                case "default_colors_set":
                    try require(args, 2)
                    foreground = try color(args[0])
                    background = try color(args[1])
                case "hl_attr_define":
                    try require(args, 2)
                    let id = try args[0].integer()
                    guard let attributes = args[1].dictionaryValue else {
                        throw StudioError.protocolError("Expected highlight attributes")
                    }
                    var highlight = EditorHighlight()
                    if let value = attributes[.string("foreground")] { highlight.foreground = try color(value) }
                    if let value = attributes[.string("background")] { highlight.background = try color(value) }
                    highlight.bold = attributes[.string("bold")]?.boolValue == true
                    highlight.italic = attributes[.string("italic")]?.boolValue == true
                    highlight.reverse = attributes[.string("reverse")]?.boolValue == true
                    highlight.underline = attributes[.string("underline")]?.boolValue == true
                    highlights[id] = highlight
                case "mode_change":
                    try require(args, 1)
                    mode = try args[0].text()
                default:
                    // Neovim permits additional UI events and trailing parameters.
                    break
                }
            }
        }
    }

    private func require(_ args: [MessagePackValue], _ count: Int) throws {
        guard args.count >= count else { throw StudioError.protocolError("Incomplete redraw event") }
    }

    private func color(_ value: MessagePackValue) throws -> Int? {
        let color = try value.integer()
        guard color >= -1, color <= 0xFFFFFF else {
            throw StudioError.protocolError("Invalid RGB color")
        }
        return color == -1 ? nil : color
    }

    private func unsupportedGrid() -> StudioError {
        .protocolError("This prototype supports one Neovim grid")
    }
}
