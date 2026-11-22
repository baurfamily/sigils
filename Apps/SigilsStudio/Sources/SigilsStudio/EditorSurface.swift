import StudioCore
@_spi(Backends) import SwiftCrossUI

#if os(macOS)
import AppKit

struct EditorSurface: View {
    let workspace: WorkspaceModel
    let body = EmptyView()

    func asWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren, backend: Backend
    ) -> Backend.Widget {
        let container = backend.createContainer()
        guard let native = container as? NSView else {
            workspace.report("The Neovim viewport requires the AppKit backend.")
            return container
        }
        let view = NeovimView(workspace: workspace)
        view.autoresizingMask = [.width, .height]
        native.addSubview(view)
        return container
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget, children: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize, environment: EnvironmentValues, backend: Backend
    ) -> ViewLayoutResult {
        .leafView(size: proposedSize.replacingUnspecifiedDimensions(by: ViewSize(720, 420)))
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget, children: any ViewGraphNodeChildren,
        layout: ViewLayoutResult, environment: EnvironmentValues, backend: Backend
    ) {
        backend.setSize(of: widget, to: layout.size.vector)
        guard let native = widget as? NSView,
              let view = native.subviews.first as? NeovimView else { return }
        view.frame = native.bounds
        view.grid = workspace.grid
        view.needsDisplay = true
        view.updateGridSize()
    }
}

// AppKit calls this legacy, nonisolated SDK protocol on the main thread.
final class NeovimView: NSView, @preconcurrency NSTextInputClient {
    private weak var workspace: WorkspaceModel?
    var grid = EditorGrid()
    private let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private let cellWidth: CGFloat = 9
    private let cellHeight: CGFloat = 22
    private var marked = ""

    init(workspace: WorkspaceModel) {
        self.workspace = workspace
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.textArea)
        setAccessibilityLabel("Neovim editor")
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { workspace?.installShortcuts(in: window) }
        window?.makeFirstResponder(self)
    }

    func updateGridSize() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        workspace?.resize(
            columns: min(1000, max(20, Int(bounds.width / cellWidth))),
            rows: min(1000, max(4, Int(bounds.height / cellHeight)))
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        color(grid.background, fallback: .textBackgroundColor).setFill()
        bounds.fill()
        for row in 0..<grid.height {
            for column in 0..<grid.width {
                let cell = grid.cells[row][column]
                let rect = NSRect(x: CGFloat(column) * cellWidth, y: CGFloat(row) * cellHeight,
                                  width: cellWidth, height: cellHeight)
                guard rect.intersects(dirtyRect) else { continue }
                let style = grid.highlights[cell.highlight]
                let background = style?.reverse == true
                    ? color(style?.foreground ?? grid.foreground, fallback: .textColor)
                    : color(style?.background ?? grid.background, fallback: .textBackgroundColor)
                background.setFill()
                rect.fill()
            }
        }
        // Paint text after all backgrounds so a wide glyph's continuation cell
        // does not erase the right half of that glyph.
        for row in 0..<grid.height {
            for column in 0..<grid.width {
                let cell = grid.cells[row][column]
                let rect = NSRect(x: CGFloat(column) * cellWidth, y: CGFloat(row) * cellHeight,
                                  width: cellWidth * 2, height: cellHeight)
                guard rect.intersects(dirtyRect), !cell.text.isEmpty else { continue }
                let style = grid.highlights[cell.highlight]
                let foreground = style?.reverse == true
                    ? color(style?.background ?? grid.background, fallback: .textBackgroundColor)
                    : color(style?.foreground ?? grid.foreground, fallback: .textColor)
                var cellFont = font
                if style?.bold == true { cellFont = NSFontManager.shared.convert(cellFont, toHaveTrait: .boldFontMask) }
                if style?.italic == true { cellFont = NSFontManager.shared.convert(cellFont, toHaveTrait: .italicFontMask) }
                var attributes: [NSAttributedString.Key: Any] = [.font: cellFont, .foregroundColor: foreground]
                if style?.underline == true { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                (cell.text as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY + 2), withAttributes: attributes)
            }
        }
        if window?.firstResponder === self {
            var rect = cursorRect
            if grid.mode.hasPrefix("insert") { rect.size.width = 2 }
            NSColor.controlAccentColor.withAlphaComponent(0.55).setFill()
            rect.fill()
        }
        if !marked.isEmpty {
            (marked as NSString).draw(at: cursorRect.origin,
                withAttributes: [.font: font, .foregroundColor: NSColor.textColor,
                                 .underlineStyle: NSUnderlineStyle.single.rawValue])
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let workspace, workspace.ready else { return }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "s": workspace.save()
            case "v":
                if let text = NSPasteboard.general.string(forType: .string) { workspace.client.paste(text) }
                else { workspace.report("The clipboard does not contain text.") }
            case "c":
                workspace.client.copySelection { result in
                    switch result {
                    case .failure(let error): workspace.report(error.description)
                    case .success(let text):
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }
            default: super.keyDown(with: event)
            }
            return
        }
        let names: [UInt16: String] = [
            53: "Esc", 36: "CR", 76: "CR", 48: "Tab", 51: "BS", 117: "Del",
            123: "Left", 124: "Right", 125: "Down", 126: "Up",
            115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
        ]
        if let name = names[event.keyCode], !hasMarkedText() {
            let shift = event.modifierFlags.contains(.shift) ? "S-" : ""
            let control = event.modifierFlags.contains(.control) ? "C-" : ""
            workspace.client.input("<\(control)\(shift)\(name)>")
        } else if event.modifierFlags.contains(.control),
                  let character = event.charactersIgnoringModifiers, character.count == 1 {
            workspace.client.input("<C-\(character.lowercased())>")
        } else {
            interpretKeyEvents([event])
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMouse(event, button: "left", action: "press")
    }
    override func mouseUp(with event: NSEvent) { sendMouse(event, button: "left", action: "release") }
    override func mouseDragged(with event: NSEvent) { sendMouse(event, button: "left", action: "drag") }
    override func scrollWheel(with event: NSEvent) {
        if event.scrollingDeltaY != 0 {
            sendMouse(event, button: "wheel", action: event.scrollingDeltaY > 0 ? "up" : "down")
        }
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let attributed = string as? NSAttributedString { text = attributed.string }
        else if let plain = string as? String { text = plain }
        else { workspace?.report("Unsupported text input"); return }
        marked = ""
        if !text.isEmpty { workspace?.client.input(text.replacingOccurrences(of: "<", with: "<LT>")) }
        needsDisplay = true
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let attributed = string as? NSAttributedString { marked = attributed.string }
        else if let plain = string as? String { marked = plain }
        else { workspace?.report("Unsupported marked text"); return }
        needsDisplay = true
    }
    func unmarkText() { marked = ""; needsDisplay = true }
    func hasMarkedText() -> Bool { !marked.isEmpty }
    func markedRange() -> NSRange { marked.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: marked.utf16.count) }
    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func characterIndex(for point: NSPoint) -> Int { NSNotFound }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        window?.convertToScreen(convert(cursorRect, to: nil)) ?? .zero
    }

    private var cursorRect: NSRect {
        NSRect(x: CGFloat(grid.cursorColumn) * cellWidth, y: CGFloat(grid.cursorRow) * cellHeight,
               width: cellWidth, height: cellHeight)
    }

    private func sendMouse(_ event: NSEvent, button: String, action: String) {
        guard let workspace, workspace.ready else { return }
        let point = convert(event.locationInWindow, from: nil)
        let row = Int(point.y / cellHeight)
        let column = Int(point.x / cellWidth)
        guard row >= 0, row < grid.height, column >= 0, column < grid.width else { return }
        workspace.client.mouse(button: button, action: action, row: row, column: column)
    }

    private func color(_ rgb: Int?, fallback: NSColor) -> NSColor {
        guard let rgb else { return fallback }
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                       green: CGFloat((rgb >> 8) & 255) / 255,
                       blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}
#else
struct EditorSurface: View {
    let workspace: WorkspaceModel
    var body: some View {
        Text("The native editor viewport is currently available on macOS only.")
    }
}
#endif
