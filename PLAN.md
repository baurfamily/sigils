# Sigils implementation plan

This is a working order of discussion and implementation, editable by the language
designer at any time. Confirmed cases in `Spec/TestCases` take priority. Do not edit
specs without explicit permission, and stop feature work whenever existing cases fail.

## Current foundation

- Swift package with one shared interpreter for REPL, files, STDIN, and YAML cases.
- Numbers, single-line double-quoted literal strings, consuming `!print`, and
  stack-plus-following-literal addition.
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
2. Confirm numeric semantics: binary floating point versus decimal/arbitrary-precision
   numbers, overflow, numeric syntax, formatting, and eventual division. `Double`
   is sufficient for current cases but not exact decimal or large-integer work.
3. Confirm operand evaluation and stack semantics before expanding arithmetic.
   Current `+` takes its left operand from the stack and a literal on its right.
   Decide whether right operands may be variables, calls, or expressions, and how
   nested prefix operations are delimited. Avoid silently introducing conventional
   infix precedence into a prefix-oriented language.
4. Add designer-approved cases for strings and lexical rules: escapes, quote pairs,
   interpolation, symbols, comments, and invalid input. Implement only those rules.
5. Discuss variable bindings and consuming versus peeking/random stack access.
   Specify underflow, index direction, and the meaning of bare `?`/`@` forms first.
6. Resolve function stack ownership, arguments, return counts, and scope before
   implementation. Private function stacks with explicit transfers may be easier
   to reason about than shared mutable stacks, but this needs designer approval.
7. Decide array construction/grouping, then loops and control flow; add cases
   incrementally rather than treating uncertain examples as finalized syntax.
8. Verify Linux and Windows builds and interactive behavior, then add continuous
   platform checks once a hosting/CI setup is chosen.

## Design notes to revisit

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
