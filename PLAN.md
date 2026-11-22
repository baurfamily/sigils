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
