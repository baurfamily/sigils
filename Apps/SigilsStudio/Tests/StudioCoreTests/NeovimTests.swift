import Foundation
import Testing
@testable import StudioCore

@MainActor
private func start(_ client: NeovimClient) async throws {
    let executable = try NeovimClient.executable()
    try await withCheckedThrowingContinuation { continuation in
        client.start(executable: executable, width: 60, height: 20) {
            continuation.resume(with: $0)
        }
    }
}

@MainActor
private func source(_ client: NeovimClient) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        client.source { continuation.resume(with: $0) }
    }
}

@MainActor
private func waitForSource(_ expected: String, client: NeovimClient) async throws {
    for _ in 0..<80 {
        if try await source(client) == expected { return }
        try await Task.sleep(for: .milliseconds(25))
    }
    throw StudioError.timeout("Expected edited buffer \(String(reflecting: expected))")
}

@Test @MainActor func embeddedNeovimEditsRunsResizesAndStops() async throws {
    let client = NeovimClient()
    defer { client.stop() }
    var frames: [EditorGrid] = []
    var failures: [String] = []
    client.onGrid = { frames.append($0) }
    client.onFailure = { failures.append($0.description) }
    try await start(client)
    #expect(client.ready)
    #expect(client.running)
    try await withCheckedThrowingContinuation { continuation in
        client.setSource("10\n20\n+") { continuation.resume(with: $0) }
    }
    client.input("gg0iX<Esc>")
    try await waitForSource("X10\n20\n+", client: client)
    client.input("gg0x")
    try await waitForSource("10\n20\n+", client: client)
    let run = ScriptRun.execute(try await source(client))
    #expect(run.stack.map(\.text) == ["30"])
    client.input("gg0i\"é中\"<Esc>")
    try await waitForSource("\"é中\"10\n20\n+", client: client)
    client.resize(width: 70, height: 22)
    for _ in 0..<80 {
        if frames.last?.width == 70, frames.last?.height == 22 { break }
        try await Task.sleep(for: .milliseconds(25))
    }
    #expect(frames.last?.width == 70)
    #expect(frames.last?.height == 22)
    #expect(failures.isEmpty)
    client.stop()
    for _ in 0..<80 {
        if !client.running { break }
        try await Task.sleep(for: .milliseconds(25))
    }
    #expect(!client.running)
}

@Test @MainActor func fileCommandsHandleSpacesAndKeepUnsavedChanges() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sigils-studio-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer {
        do { try FileManager.default.removeItem(at: directory) }
        catch { Issue.record("Unable to remove fixture: \(error)") }
    }
    let file = directory.appendingPathComponent("example with spaces.sigils")
    try "1 2 +".write(to: file, atomically: true, encoding: .utf8)
    let client = NeovimClient()
    defer { client.stop() }
    try await start(client)
    try await withCheckedThrowingContinuation { continuation in
        client.open(file.path) { continuation.resume(with: $0) }
    }
    #expect(try await source(client) == "1 2 +")
    client.input("gg0i9 <Esc>")
    try await waitForSource("9 1 2 +", client: client)
    let openFailure: Bool = await withCheckedContinuation { continuation in
        client.open(directory.appendingPathComponent("other.sigils").path) {
            if case .failure = $0 { continuation.resume(returning: true) }
            else { continuation.resume(returning: false) }
        }
    }
    #expect(openFailure)
    #expect(try await source(client) == "9 1 2 +")
    try await withCheckedThrowingContinuation { continuation in
        client.save { continuation.resume(with: $0) }
    }
    #expect(try String(contentsOf: file, encoding: .utf8) == "9 1 2 +\n")
}

@Test @MainActor func missingNeovimFailsExplicitly() async {
    let client = NeovimClient()
    let failed: Bool = await withCheckedContinuation { continuation in
        client.start(executable: URL(fileURLWithPath: "/nonexistent/sigils-nvim"), width: 60, height: 20) {
            if case .failure = $0 { continuation.resume(returning: true) }
            else { continuation.resume(returning: false) }
        }
    }
    #expect(failed)
    #expect(!client.ready)
    #expect(!client.running)
}
