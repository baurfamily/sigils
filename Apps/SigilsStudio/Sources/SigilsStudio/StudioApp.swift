import DefaultBackend
import SwiftCrossUI

@main
struct StudioApp: App {
    var body: some Scene {
        WindowGroup("Sigils Studio") {
            WorkspaceView()
        }
        .defaultSize(width: 1100, height: 760)
    }
}

struct WorkspaceView: View {
    @State private var workspace = WorkspaceModel(initialPath: CommandLine.arguments.dropFirst().first)

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            debugToolbar
            if let error = workspace.error {
                Text(error).foregroundColor(.red)
            }
            HStack(alignment: .top, spacing: 8) {
                EditorSurface(workspace: workspace)
                    .frame(minWidth: 420, minHeight: 220)
                sidebar.frame(width: 240)
            }
            Text(workspace.status).font(.caption)
            Divider()
            output
        }
        .padding(12)
        .onAppear { workspace.start() }
        .onDisappear { workspace.stop() }
    }

    private var toolbar: some View {
        HStack {
            TextField("File path (:e and :w also work in Neovim)", text: $workspace.path)
            Button("Open") { workspace.open() }.disabled(!workspace.ready)
            Button("Save") { workspace.save() }.disabled(!workspace.ready)
            Button(workspace.running ? "Running..." : "Run (Cmd-R)") { workspace.run() }
                .disabled(!workspace.ready || workspace.running)
        }
    }

    private var debugToolbar: some View {
        HStack {
            Button("Debug / Restart (Cmd-D)") { workspace.debugAction(.start) }
                .disabled(!workspace.ready || workspace.running)
            Button("Instruction (Cmd-J)") { workspace.debugAction(.instruction) }
                .disabled(!workspace.canStep)
            Button("Line (Cmd-Shift-J)") { workspace.debugAction(.line) }
                .disabled(!workspace.canStep)
            Button("To Cursor (Cmd-Shift-C)") { workspace.debugAction(.cursor) }
                .disabled(!workspace.canStep)
            Button("Stop (Cmd-.)") { workspace.stopDebug() }
                .disabled(!workspace.running && workspace.debug == nil)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stack · top first").font(.headline)
            if let result = workspace.result {
                if result.stack.isEmpty { Text("(empty)").foregroundColor(.gray) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(result.stack, id: \.index) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text("@\(entry.index)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .frame(width: 40, alignment: .leading)
                                Divider()
                                Text(entry.text)
                                    .font(.system(size: 14, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Divider()
                                Text(entry.kind)
                                    .font(.caption)
                                    .foregroundColor(typeColor(entry.kind))
                                    .frame(width: 48, alignment: .leading)
                            }
                            .padding(4)
                            Divider()
                        }
                    }
                }
            } else {
                Text("Run the buffer to inspect its stack.").foregroundColor(.gray)
            }
            Spacer()
        }
    }

    private func typeColor(_ kind: String) -> Color {
        switch kind {
        case "number": .blue
        case "string": .green
        case "null": .purple
        case "error": .red
        case "function": .orange
        default: .gray
        }
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Output / diagnostics").font(.headline)
            if let diagnostic = workspace.result?.diagnostic {
                Text(diagnostic).foregroundColor(.red)
            }
            ScrollView {
                Text(workspace.result.map { $0.output.isEmpty ? "(no output)" : $0.output } ?? "(no output)")
                    .font(.system(size: 13, design: .monospaced))
                    .textSelectionEnabled()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 140)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
