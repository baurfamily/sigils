import Sigils

public struct DebugRun: Sendable {
    public let source: String
    private var session: ExecutionSession

    public var nextLocation: SourceLocation? { session.nextLocation }
    public var lastInstruction: SourceSpan? { session.lastInstruction }
    public var isFinished: Bool { session.isFinished }
    public var result: ScriptRun {
        .snapshot(stack: session.stack, output: session.output, diagnostic: session.error?.description)
    }

    public init(source: String) {
        self.source = source
        session = ExecutionSession(source: source)
    }

    public mutating func stepInstruction() { session.step() }

    public mutating func stepLine() {
        guard let line = nextLocation?.line else { return }
        repeat { session.step() }
        while nextLocation?.line == line
    }

    /// Stops before the first instruction on or after the editor cursor's line.
    public mutating func runToLine(_ line: Int) {
        while let next = nextLocation, next.line < line { session.step() }
    }
}
