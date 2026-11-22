#if os(macOS)
import AppKit
import StudioCore
import Testing
@testable import SigilsStudio

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<120 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(25))
    }
    throw StudioError.timeout("Workspace condition")
}

@MainActor
private func source(_ model: WorkspaceModel) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        model.client.source { continuation.resume(with: $0) }
    }
}

@MainActor
private func shortcut(_ key: String, shift: Bool = false) throws -> NSEvent {
    try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: shift ? [.command, .shift] : [.command],
        timestamp: 0, windowNumber: 0, context: nil, characters: key,
        charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0
    ))
}

@Test @MainActor func nativeTextInputRunAndRecovery() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sigils-workspace-\(UUID().uuidString)")
    let model = WorkspaceModel(recoveryDirectory: directory)
    defer {
        model.stop()
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Unable to remove workspace fixture: \(error)") }
    }
    model.start()
    try await waitUntil { model.ready || model.error != nil }
    #expect(model.error == nil, "\(model.error ?? "")")
    #expect(model.ready)
    let view = NeovimView(workspace: model)
    view.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
    view.updateGridSize()
    model.client.input("ggdGi")
    try await waitUntil { model.grid.mode.hasPrefix("insert") }
    view.insertText("\"hello <world>\"", replacementRange: NSRange(location: NSNotFound, length: 0))
    let escape = try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53
    ))
    view.keyDown(with: escape)
    try await waitUntil { model.grid.mode == "normal" }
    #expect(try await source(model) == "\"hello <world>\"")
    model.run()
    try await waitUntil { model.result != nil && !model.running }
    #expect(model.result?.stack.map(\.text) == ["\"hello <world>\""])
    #expect(model.result?.diagnostic == nil)
    #expect(model.error == nil, "\(model.error ?? "")")
    let draft = directory.appendingPathComponent("draft.sigils")
    #expect(try String(contentsOf: draft, encoding: .utf8) == "\"hello <world>\"")

    view.grid = model.grid
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 300, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    #expect(bitmap.colorAt(x: 10, y: 10) != nil)

    model.client.input("gg0i1 <Esc>")
    try await waitUntil { model.status.contains("Buffer changed") }
    #expect(model.result?.stack.map(\.text) == ["\"hello <world>\""])
    model.path = directory.appendingPathComponent("saved draft.sigils").path
    model.save()
    let saved = URL(fileURLWithPath: model.path)
    try await waitUntil { FileManager.default.fileExists(atPath: saved.path) }
    #expect(try String(contentsOf: saved, encoding: .utf8) == "1 \"hello <world>\"\n")
}

@Test @MainActor func workspaceOpensRequestedFileAndUsesScriptErrors() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sigils-workspace-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let file = directory.appendingPathComponent("script.sigils")
    try "7\n!print\n1\n+".write(to: file, atomically: true, encoding: .utf8)
    let model = WorkspaceModel(recoveryDirectory: directory, initialPath: file.path)
    defer {
        model.stop()
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Unable to remove workspace fixture: \(error)") }
    }
    model.start()
    try await waitUntil { model.ready || model.error != nil }
    #expect(model.error == nil, "\(model.error ?? "")")
    #expect(try await source(model) == "7\n!print\n1\n+")
    model.run()
    try await waitUntil { model.result != nil && !model.running }
    #expect(model.result?.output == "7\n")
    #expect(model.result?.stack.map(\.text) == ["1"])
    #expect(model.result?.diagnostic?.hasPrefix("4:1: stack-underflow:") == true)
}

@Test @MainActor func debugHotkeysStepRunToCursorRestartAndInvalidateEdits() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sigils-debug-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let file = directory.appendingPathComponent("debug.sigils")
    try "1 2 +\n\n3 *\n!print".write(to: file, atomically: true, encoding: .utf8)
    let model = WorkspaceModel(recoveryDirectory: directory, initialPath: file.path)
    defer {
        model.stop()
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Unable to remove debugger fixture: \(error)") }
    }
    model.start()
    try await waitUntil { model.ready || model.error != nil }
    #expect(model.ready)
    #expect(model.handleShortcut(try shortcut("d")))
    try await waitUntil { model.debug != nil && !model.running }
    #expect(model.debug?.nextLocation?.line == 1)
    #expect(model.result?.stack.isEmpty == true)
    #expect(model.handleShortcut(try shortcut("j")))
    try await waitUntil { model.result?.stack.map(\.text) == ["1"] && !model.running }
    #expect(model.handleShortcut(try shortcut("j", shift: true)))
    try await waitUntil { model.debug?.nextLocation?.line == 3 && !model.running }
    #expect(model.result?.stack.map(\.text) == ["3"])

    model.client.input("G")
    for _ in 0..<80 {
        let line: Int = try await withCheckedThrowingContinuation { continuation in
            model.client.snapshot { continuation.resume(with: $0.map(\.cursorLine)) }
        }
        if line == 4 { break }
        try await Task.sleep(for: .milliseconds(25))
    }
    #expect(model.handleShortcut(try shortcut("c", shift: true)))
    try await waitUntil { model.debug?.nextLocation?.line == 4 && !model.running }
    #expect(model.result?.stack.map(\.text) == ["9"])
    #expect(model.result?.output == "")
    #expect(model.handleShortcut(try shortcut("j", shift: true)))
    try await waitUntil { model.debug?.isFinished == true && !model.running }
    #expect(model.result?.output == "9\n")
    #expect(model.error == nil, "\(model.error ?? "")")

    model.handleShortcut(try shortcut("d"))
    try await waitUntil { model.debug?.nextLocation?.line == 1 && !model.running }
    model.client.input("gg0i10 <Esc>")
    try await waitUntil { model.debugInvalidated }
    #expect(!model.canStep)
    model.handleShortcut(try shortcut("j"))
    #expect(model.error?.contains("source changed") == true)
    #expect(model.result?.stack.isEmpty == true)
    model.handleShortcut(try shortcut("d"))
    try await waitUntil { !model.debugInvalidated && !model.running }
    model.handleShortcut(try shortcut("j"))
    try await waitUntil { model.result?.stack.map(\.text) == ["10"] && !model.running }
    model.handleShortcut(try shortcut("."))
    #expect(model.debug == nil)
    #expect(model.status.contains("stopped"))
    model.handleShortcut(try shortcut("r"))
    try await waitUntil { model.result?.output == "9\n" && !model.running }
    #expect(model.result?.stack.map(\.text) == ["10"])
    #expect(!model.handleShortcut(try shortcut("v")))
}

@Test @MainActor func cancellingAnInflightDebugRequestDoesNotRestoreItsState() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sigils-debug-\(UUID().uuidString)")
    let model = WorkspaceModel(recoveryDirectory: directory)
    defer {
        model.stop()
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Unable to remove debugger fixture: \(error)") }
    }
    model.start()
    try await waitUntil { model.ready || model.error != nil }
    model.debugAction(.start)
    model.stopDebug()
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.debug == nil)
    #expect(model.result == nil)
    #expect(!model.running)
}

@Test @MainActor func runShortcutIsIndependentOfFilePathFocus() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sigils-shortcuts-\(UUID().uuidString)")
    let model = WorkspaceModel(recoveryDirectory: directory)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer {
        model.stop()
        window.close()
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Unable to remove shortcut fixture: \(error)") }
    }
    model.start()
    try await waitUntil { model.ready || model.error != nil }
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
    window.contentView?.addSubview(field)
    window.makeFirstResponder(field)
    model.installShortcuts(in: window)
    let event = try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: "r",
        charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15
    ))
    #expect(model.handleShortcut(event))
    try await waitUntil { model.result != nil && !model.running }
    #expect(model.result?.stack.map(\.text) == ["10"])
    #expect(model.result?.output == "40\n")
    #expect(field.stringValue.isEmpty)
    #expect(model.error == nil, "\(model.error ?? "")")
}
#endif
