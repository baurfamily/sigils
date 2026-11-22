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
2. Review `Spec/TestCases/04-variable-storage.yml` while implementing basic postfix
   variable storage. `5 ->x` consumes the top value and stores it in `x`; bare `x`
   pushes the current value, not a reference. Undefined reads, bare `->`, and detached
   `-> x` are errors. The destination must be attached to the arrow.
   The file proposes successful cases and semantic error categories; approve the
   error-assertion schema and settle identifier rules and scope before implementation.
   Cases now live in TestCases with optional low/medium/high confidence metadata.
   Confidence never skips or relaxes a case. Storage underflow is medium confidence;
   all other variable cases are high. Variables and error assertions are not yet
   implemented, so these cases currently fail; resolve them before unrelated features.
3. Revisit numeric semantics: binary floating point versus decimal/arbitrary-precision
   numbers, overflow, numeric syntax, and formatting. True division using `Double`
   is currently confirmed, but not exact decimal or large-integer arithmetic.
4. Add designer-approved cases for strings and lexical rules: escapes, quote pairs,
   interpolation, symbols, comments, and invalid input. Implement only those rules.
5. Discuss consuming versus peeking/random stack access.
   Specify underflow, index direction, and the meaning of bare `?`/`@` forms first.
6. Resolve function stack ownership, arguments, return counts, and scope before
   implementation. Private function stacks with explicit transfers may be easier
   to reason about than shared mutable stacks, but this needs designer approval.
7. Decide array construction/grouping, then loops and control flow; add cases
   incrementally rather than treating uncertain examples as finalized syntax.
8. Verify Linux and Windows builds and interactive behavior, then add continuous
   platform checks once a hosting/CI setup is chosen.

## Design notes to revisit

- Interim error policy agreed, pending implementation: errors become structured stack
  values in the REPL; scripts stop on an error until try/rescue semantics exist.
  Preserve the current arithmetic/null policy rather than introducing new arithmetic
  error values in this step. This does not decide how every arithmetic failure behaves.
  Distinguish parser failures (where the next instruction may be unclear) from
  operation failures (such as future file/network reads) that callers could recover.
  A future rescue operator may inspect an error on the stack; its syntax, whether it
  checks only the top or deeper entries, and continuation boundaries are deferred,
  potentially until functions/methods exist.
- Before implementing stack errors, settle their representation and source-location
  assertions, failed-instruction operand effects, which prior state/output survives,
  and where a failed REPL submission stops. The implementation currently throws and
  rolls back the entire submission; it does not yet implement the interim stack-error
  policy. Keep the variable draft's error assertions provisional until this is settled.
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
- Decide whether runtime failures should eventually retain partial stack mutations
  or streamed output. Currently each execution commits only on success.
- Define an error-expectation schema with the designer before adding error cases to
  the YAML files; current error behavior is covered by Swift implementation tests.
