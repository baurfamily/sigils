# Sigils implementation plan

This is a working order of discussion and implementation, editable by the language
designer at any time. Confirmed cases in `Spec/TestCases` take priority. Do not edit
specs without explicit permission, and stop feature work whenever existing cases fail.

## Current foundation

- Swift package with one shared interpreter for REPL, files, STDIN, and YAML cases.
- Numbers, single-line double-quoted literal strings, consuming `!print`,
  postfix stack-only arithmetic (`+`, `-`, `*`, `/`), and postfix string concatenation.
- Binary operators consume the top as the right operand and the next as the left;
  they never read ahead. Infix behavior has been removed with designer approval.
- True `Double` division; division by zero produces a null stack value.
- Attached postfix storage (`->x`), value reads, and rebinding in one interpreter
  namespace. Case-sensitive ASCII names start with a letter/underscore and continue
  with letters, digits, or underscores; REPL bindings persist across submissions.
- Attached peek storage (`?->name`) inspects the top value without consuming or
  duplicating it; the destination receives its current value. Uses the same
  naming and underflow rules as consuming storage.
- Random access moves (`@index`) or copies (`?@index`) an entry to the top. Indexed
  storage replaces destinations (`->@index`, `?->@index`). Experimental consuming
  insertion (`->?@index`) is available for REPL exploration at low confidence.
- First-error stopping with successful prefix state/output retained. Failed
  instructions retain operands; REPL errors are structured stack values, while
  scripts stop with a diagnostic and nonzero exit.
- YAML discovery on every run; isolated cases, output/stack assertions, failure
  diagnostics, and a test-suite entry point for the current cases.
- No broader brainstorming features implemented.

The package, unit tests, current YAML cases, and REPL/file/STDIN modes have been
verified on macOS. Recursive discovery, mismatches, malformed YAML, missing paths,
and failure exit statuses have also been exercised. Linux and Windows validation
remain pending.

## Workspace UX direction and initial prototype

Keep the quick terminal REPL; a richer workspace is an additional interface, not
a replacement. The pre-workspace checkpoint is `5e3cc5c`. The optional desktop
package `Apps/SigilsStudio` now uses SwiftCrossUI 0.9.0 and MessagePack.swift.
The initial macOS viewport embeds Neovim 0.10+, with Open/Save, Run, a vertical
top-first stack viewer, output/diagnostics, and one local recovery draft.
It now also supports instruction/line stepping, line-based Run to Cursor,
execution highlighting, and window-wide Run/debug/save shortcuts.
CLI dependencies and language semantics remain unchanged.

The portable protocol/grid and script execution layers, native input, file saves,
recovery, and editor process shutdown are tested. A real 1100 x 760 content window
was launched; external screenshot capture was unavailable in this environment.
Linux/Windows native viewport adapters and packaging remain pending. The prototype
explicitly reports unsupported platforms instead of substituting another editor.
Use the native SwiftPM build system on Swift 6.4 to avoid SwiftBuild compiling
the UI dependency's Android shim on macOS.

### Quick REPL follow-up

- Add session history with Up/Down, basic cursor movement, and Ctrl-A/Ctrl-E.
  Preserve redirected-input behavior, EOF, Unicode text, and terminal restoration.
  Evaluate line editors for actual platform support; do not assume a macOS library
  also works on Linux or Windows.
- The designer approved `!stack:clear` as a language operation for both scripts and
  the REPL. It is not implemented yet. Clear stack entries, including stored errors,
  without clearing variable bindings or producing output; an empty stack is fine.
  Keep `!print` unchanged. Other namespaced built-ins, including `!console:print`,
  require separate discussion. Do not add or modify YAML cases without permission.

### Workspace architecture options

1. **Desktop GUI with embedded Neovim (chosen for the initial slice):** a Swift-owned window with an editor,
   attached stack sidebar, output/diagnostic pane, and debugger controls.
   SwiftCrossUI is the prototype dependency. Its DefaultBackend
   uses AppKit on macOS, WinUI on Windows, and GTK on Linux; it is still a
   work-in-progress and custom editor rendering needs a feasibility prototype.
   Apple SwiftUI alone would not meet the desktop cross-platform goal.
2. **Swift-owned terminal workspace with embedded Neovim:** SwiftTUI is a
   candidate for layout, but the inspected version keeps custom primitive controls
   and keyboard dispatch internal. A Neovim viewport would need framework
   extensions or a different host, not simply a TextField. Prove this before
   committing to a fork or building the full workspace.
3. **Neovim-hosted workspace:** a Neovim plugin/front-end with a Swift execution
   backend. Splits/floating windows supply stack and output views. This avoids
   writing an editor renderer but makes the product primarily a Neovim plugin.

All options keep language semantics and debugging in Swift. Prefer a separate
optional app package for a GUI so its platform libraries and build requirements
do not burden CLI users or headless interpreter/spec tests.

### Embedded editor boundary

Neovim owns editing, buffers, undo, modes, and cursor movement; Swift owns Sigils
execution and workspace/debugger state. The installed Neovim is 0.10.2.

- Use `nvim --embed` with a MessagePack-RPC channel over child-process pipes.
  Query API capabilities and attach a UI; do not combine UI embedding with
  `--headless`. No network listener is needed.
- Start with one `ext_linegrid` viewport. The host still must render grid cells,
  highlights, scrolling, and the cursor, and forward keyboard/mouse input and
  resizes. Apply redraws at `flush` boundaries. Embedding is not a ready-made
  editor widget.
- Prototype Unicode, cell widths, clipboard/paste, focus and key handling,
  resize, and child shutdown before assuming cross-platform viability.
  GUI rendering/input may need small platform-specific adapters.
- Start with predictable editor configuration; loading personal Neovim config
  should be an explicit later option. Surface missing Neovim, RPC errors, and
  child-process failures rather than silently switching editors.

### Execution and debugger boundary

- `ExecutionSession` now pauses the existing parser/executor at real instruction
  boundaries. Ordinary execution and debugging share this path, preserving lazy
  parsing, first-error stopping, successful prefix state/output, and
  failed-instruction atomicity. Sessions expose source spans and next locations.
- A debug run uses an immutable source snapshot and a fresh stack/bindings.
  Track instruction source spans and original line/column locations. Distinguish
  the editor cursor from the execution position.
- Expose state and newly produced output after each step. Show the stack vertically,
  top/index 0 first, with values/types and an empty-stack state. Keep diagnostic
  information visible without confusing errors with strings.
- Full-script debug errors follow script stopping semantics, not REPL error
  insertion. A scratch command console can retain REPL semantics in its own
  persistent session; mutating a paused debug session needs an explicit decision.
- Source edits invalidate the paused run. Clearly mark stale state and require
  restart rather than silently continuing against changed source.
- Implemented commands: Run, Start Debug/Restart, Step Instruction, Step Line,
  Run to Cursor, and Stop. Run to Cursor stops before the first instruction on or
  after the cursor line; it never replays earlier instructions or goes backwards.
  Step Line consumes the remaining instructions on the next executable line.
  Stop rejects pending results rather than interrupting an instruction halfway.
  Defer Step Over/Into/Out until functions exist.
- macOS shortcuts are window-wide: Cmd-R runs, Cmd-D starts/restarts debugging,
  Cmd-J steps an instruction, Cmd-Shift-J steps a line, Cmd-Shift-C runs to the
  cursor line, Cmd-. stops, and Cmd-S saves. Personal Neovim mappings cannot
  intercept these app commands.

### Suggested workspace milestones

1. Initial GUI feasibility slice is implemented on macOS: an editable embedded
   Neovim viewport, stack/output panels, Run, Open/Save, resize, and lifecycle checks.
2. Keep the small REPL improvements independent; do not expand GUI polish first.
3. Resumable execution is implemented and tested without changing YAML expectations:
   uninterrupted/stepped results, errors, output, source locations, and multiple
   instructions on one line retain existing behavior.
4. Basic stepping and execution highlighting are connected. Debugger hotkeys,
   restart, cursor targeting, edit invalidation, and pending-request cancellation
   are tested against real Neovim buffers. Next focus on language/functions design,
   not every debugger command or additional editor polish.
5. Add a read-only YAML use-case browser using the existing spec runner. Preserve
   case isolation and blocking/non-blocking confidence reporting; re-discover cases
   so designer edits and new files appear. No automatic spec rewriting.
6. Validate on Linux and Windows as well as macOS. Include terminal/GUI cleanup,
   Unicode, keyboard differences, dependency setup, and packaging in acceptance.

## Suggested next order

1. Re-read all current cases and this plan; run `swift test` and `swift run sigils spec`.
   Resolve failures before changing language behavior.
2. Review the now-implemented basic variable rules in `Spec/TestCases/04-variable-storage.yml`
   as new cases arise. `5 ->x` consumes the top value; bare `x` pushes its current
   value rather than a reference. Undefined reads, bare `->`, and detached `-> x`
   are errors. All variable cases and category assertions now pass.
   Low-confidence cases run and report results without behavioral failures blocking
   the suite; medium/high and unmarked cases remain blocking. Invalid schemas still fail.
   Storage underflow remains medium confidence; keep it under review during loop design.
3. Revisit numeric semantics: binary floating point versus decimal/arbitrary-precision
   numbers, overflow, numeric syntax, and formatting. True division using `Double`
   is currently confirmed, but not exact decimal or large-integer arithmetic.
4. Add designer-approved cases for strings and lexical rules: escapes, quote pairs,
   interpolation, symbols, comments, and invalid input. Implement only those rules.
5. Discuss random stack access and possible inspection modifiers separately from
   functions. Move/copy and replacement cases in `06.00-stack-reading.yml` and
   `06.01-stack-replacement.yml` now pass. Try the low-confidence insertion syntax
   from `06.02-stack-insertion.yml` in the REPL before finalizing the mnemonic and
   gap indexing. Its cases execute as non-blocking experiments, not skipped tests.
6. Resolve function stack ownership, arguments, return counts, and scope before
   implementation. Private function stacks with explicit transfers may be easier
   to reason about than shared mutable stacks, but this needs designer approval.
7. Decide array construction/grouping, then loops and control flow; add cases
   incrementally rather than treating uncertain examples as finalized syntax.
8. Verify Linux and Windows builds and interactive behavior, then add continuous
   platform checks once a hosting/CI setup is chosen.

## Design notes to revisit

- Random-access cases propose `@index` as move-to-top and `?@index` as copy-to-top,
  not swapping and not a special storage selector. Indices refer to the current
  stack: zero counts from the top, negative one from the bottom; index variables
  are read without changing their bindings. Other entries retain relative order.
- Replacement cases propose `->@index` consuming the top source and replacing the
  selected entry, with the destination resolved before consumption. Self-replacement
  is a no-op; `?->@index` preserves the source while replacing the destination.
  These rules are medium confidence and implemented.
- Low-confidence insertion syntax `->?@index` could preserve the destination entry
  rather than replace it, while still consuming the source. This is a plausible
  meaning of "do not consume" applied to the destination, not a settled modifier rule.
  The insertion implementation uses the file's sketched gap indices: zero above top, positive
  indices counting downward, negative one below bottom. Resolve against the original
  stack and adjust for source removal. Gap indexing and modifier placement remain
  provisional. Combined source-preserving insertion `?->?@index` is rejected until
  its semantics are discussed.
- `invalid-stack-index` and `stack-index-out-of-bounds` are implemented. Indexed writes
  without a source expect `stack-underflow`. Out-of-bounds/invalid-index failures
  should leave the source and other entries unchanged.
- `?` generally signals inspection without consumption and is a modifier, not a
  standalone duplicate operator. Storage and copy-to-top are supported; arithmetic,
  printing, and comparison modifiers require separate decisions about which operands
  are preserved and what results are produced.
- Conditionals remain separate design discussion: inspecting a value to decide a
  branch is a motivation for `?`, but this does not establish branch syntax, comparison
  semantics, truth values, or whether the inspected value remains for the chosen body.
  Random access may inform these decisions; do not bundle functions into that discussion.
- `_` remains an ordinary variable, not a special stack destination. The speculative
  duplication case was removed in favor of `?@0`; keep indexed copying rather than
  introducing a special variable.
- Interim error policy implemented: errors become structured stack
  values in the REPL; scripts stop on an error until try/rescue semantics exist.
  Preserve the current arithmetic/null policy rather than introducing new arithmetic
  error values in this step. This does not decide how every arithmetic failure behaves.
  Distinguish parser failures (where the next instruction may be unclear) from
  operation failures (such as future file/network reads) that callers could recover.
  A future rescue operator may inspect an error on the stack; its syntax, whether it
  checks only the top or deeper entries, and continuation boundaries are deferred,
  potentially until functions/methods exist.
- Errors currently have category, line, column, and message fields. Each submission
  stops at its first error, preserving successful prefix state/output and leaving
  failed-instruction operands/bindings unchanged. REPL submissions append the error
  and return to the prompt. YAML `error` asserts its category; optional output/stack
  assert the prefix state without a REPL error entry. YAML source-location assertions,
  general struct access, and later propagation/rescue of stored errors remain deferred.
- Stack-consuming loops are deferred. Candidate forms `(->x x !print)` and
  `(!print)` mean "continue until it can't"; no syntax or stopping rule is final.
  Revisit whether loops preflight their required values or recognize underflow as
  normal termination, without prematurely deciding whether empty `->x` is an error.
  Array-consuming loops should be considered alongside stack-consuming loops.
- Null can deliberately delimit stack data, like a C-string terminator; this is a
  legitimate use, not necessarily a bug. Alternatives include exhaustion-based loops
  that consume null as data plus a distinct explicit stop marker. Decide whether a
  sentinel is consumed or retained, how it differs from accidental null, and how
  nested loops or partial iterations behave before choosing either model.
  Conditional loops could later skip null, stop on arbitrary values, or use a
  predicate such as the tentative `(?< 100 ->x x !print)` form. Predicate syntax,
  peeking/consumption, and termination remain design discussion, not confirmed cases.
- Forward-looking operand sigils and `x<-` storage are deferred, not implemented.
  Decide later whether "next produced value" means an individual push or the result
  of a bounded computation, and how that boundary and zero/multiple results work.
  Bare arithmetic operators will not infer a forward-reading mode from stack depth.
- Postfix arithmetic supersedes the prefix/hybrid examples in the brainstorming
  document; preserve that document as historical discussion rather than rewriting it.
- Null coercion is provisional: zero division produces null, numeric arithmetic
  propagates it, string concatenation treats it as empty text, and `!print` consumes
  it without emitting bytes. This can hide the original invalid calculation or
  silently remove text. Revisit propagation, observability, and whether absent and
  invalid values should be distinguishable before building control flow.
- A minus immediately followed by a digit remains a signed number literal; standalone
  minus is subtraction. Resolve adjacency deliberately if tokenization changes.
- Spreading signatures between the opening definition and trailing return annotation
  may make tooling and error messages harder. Consider alternatives in discussion,
  without changing the proposed syntax prematurely.
- Adjacent symbol operators can become ambiguous as more double-character forms are
  added. Establish a tokenization policy using approved examples.
- Multiline REPL input will become necessary for functions/loops. The current REPL
  intentionally evaluates one complete line at a time.
- Revisit instruction-level state/output effects when rescue exists. Current failures
  retain successful prefix instructions and output, not partial failed instructions.
- Extend the implemented YAML error-category assertions with designer-approved
  source locations or structured stack-error assertions when needed.
