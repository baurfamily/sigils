# Sigils

An experimental, symbol-oriented language implemented in Swift. Confirmed behavior
lives in `Spec/TestCases`; `Spec/brainstorming.md` is design discussion, not a finished
language definition.

## Running

Requires Swift 6.0 or newer. Run these commands from the project directory:

```sh
swift build
swift run sigils repl
swift run sigils run program.sigils
printf '"hello" !print\n' | swift run sigils run -
printf '1 4 + !print\n' | swift run sigils
swift run sigils spec
swift test
```

The executable is also available at `.build/debug/sigils`. `sigils program.sigils`
and `sigils -` are shortcuts for file and STDIN execution. With no arguments, a
terminal starts the REPL; redirected input executes as one program.

The REPL retains its stack and variable bindings between lines and displays the
stack bottom-to-top after each line. EOF (usually Ctrl-D on Unix) exits. Files and
STDIN start with an empty stack and bindings and emit only explicitly printed output.
Errors go to STDERR; noninteractive execution stops and exits unsuccessfully.

Each submission stops at its first error. Successful instructions before it retain
their state and output; the failed instruction leaves its operands and bindings
unchanged. In the REPL, a structured error value is appended to the stack and the
next prompt remains available. Its display is `err:<category, line>`; the diagnostic
also includes a column and message. Scripts do not append the REPL-only error value.
No try/rescue, automatic continuation, or general struct syntax is implemented yet.

## Supported language

| Syntax | Behavior |
| --- | --- |
| `5`, `12.2`, `-8`, `0.1` | Push a number onto the stack. |
| `"hello, world"` | Push a single-line, double-quoted string. |
| `1 4 +` | Push both numbers; `+` consumes them and pushes their sum. |
| `4 1 -`, `2 3 *`, `8 2 /` | Subtract, multiply, or divide the top two stack values. |
| `"hello" " " + "world" +` | Concatenate strings, leaving the result on the stack without printing. |
| `"hello" !print` | Consume the top value and print it with a newline. |
| `5 ->x` | Consume the top value and store it in variable `x`. |
| `5 ?->x` | Inspect the top value and store it in `x` without removing it. |
| `x` | Push the current stored value without consuming or modifying the binding. |
| Spaces and newlines | Separate instructions; `1 4+` also works. |

All binary operators are postfix and consume only the top two existing stack values:
the top is the right operand, and the value below it is the left operand. Deeper
entries are untouched. Operands can come from earlier REPL lines; an operator never
reads ahead for a value. Fewer than two stack values is an error.

There is no infix syntax or precedence system. `1 2 3 * +` produces `7`, while
`1 2 + 3 *` and `3 2 1 + *` produce `9`. `1 + 2` fails on an empty starting stack.
`-` directly followed by a digit starts a signed literal: `4 -1` pushes two numbers,
whereas `4 1 -` subtracts. Type mismatches, missing operands, unsupported syntax, and
unknown functions are errors with line/column locations. Adding a number to a string
does not implicitly convert the number to text.

### Variables

Destination names must be attached: `->x` is valid; `-> x` and bare `->` are errors,
not discard instructions. Names are case-sensitive ASCII identifiers: a letter or
underscore followed by letters, digits, or underscores. For example, `_result2`
is valid. There is one binding namespace per interpreter, with rebinding allowed.
Each spec case starts with fresh bindings.

```text
10 3 ->right ->left
left right - !print
```

This prints `7`. Reads push values rather than live binding references:
`5 ->x x 8 ->x !print` prints the earlier `5` and leaves `x` bound to `8`.
Undefined reads are errors, whereas reading a stored null succeeds. Storing with
an empty stack is currently an underflow error; this remains a medium-confidence
rule pending loop design. References, forward storage, and nested scopes are deferred.

### Peeking

`?` is a modifier meaning inspect without consuming, not a standalone duplication
instruction. For variable storage, use `?->name`. The name
follows the same rules as `->name`, and an empty stack is an underflow error.
The modifier and destination must be attached; `? ->x`, `?-> x`, and bare `?` fail.

```text
5 ?->copy ->original
copy original + !print
```

This prints `10`: peeking leaves `5` available for the consuming storage. It does
not push an extra value. The binding captures a value, not a live stack reference.
Strings, null, and REPL error values can also be inspected this way.

Modifiers on arithmetic or printing and conditionals are not
implemented. `_` remains an ordinary variable name, not a special stack destination.
Use `?@0` to duplicate the top entry.

### Random stack access

`@index` moves an entry to the top; `?@index` copies it to the top, preserving the
original. Indices refer to the current stack: `0` is the top, `1` the next entry,
`-1` the bottom, and `-2` the next entry from the bottom. Other entries keep their
relative order. An attached variable can supply the index: `@depth` or `?@depth`.
Indices must be finite whole numbers; strings, null, and fractional indices fail.

Indexed storage resolves its destination **before** consuming the top source.
`->@index` replaces the destination and removes the source from its old position;
`?->@index` preserves the source. Writing the top back to itself is a no-op.

Each example below independently starts with `10 20 30`:

| Operation | Resulting stack |
| --- | --- |
| `@1` | `10 30 20` |
| `?@0` | `10 20 30 30` |
| `->@1` | `10 30` |
| `?->@1` | `10 30 30` |
| `->?@2` | `10 30 20` |
| `->?@3` | `30 10 20` |

**Experimental insertion:** `->?@index` moves the top value into a gap without
discarding any destination entry. Gaps are resolved against the original stack:
`0` is above the top, `1` immediately below it, and `count` below the bottom.
Negative gap indices count upward from the bottom: `-1` is the bottommost gap.
Removing the source adjusts the gap as necessary; inserting into gap `0` or `1`
therefore leaves the original stack unchanged.

Insertion syntax and gap rules remain low confidence but are available in the REPL.
Combining source preservation and insertion (`?->?@index`) is not supported yet.
The behavior files are `06.00-stack-reading.yml`, `06.01-stack-replacement.yml`,
and `06.02-stack-insertion.yml`; all now execute, with low-confidence results
reported separately and non-blocking.

Invalid or out-of-bounds access leaves stack entries untouched. Reads from an empty
stack are out of bounds; indexed writes without a source report stack underflow.

Numbers currently use finite IEEE-754 `Double` values. Decimal arithmetic may round,
and integers beyond 2^53 are not all exactly representable. Whole-number output omits
the `.0` suffix. Numeric equality in specs is exact, not tolerance-based.

Division is true floating-point division: `5 2 /` produces `2.5`. Dividing by zero
(including `0 0 /` and negative zero) consumes the operands and pushes null instead
of infinity or an error. Other numeric overflow remains an error.

**Provisional null behavior:** numeric arithmetic propagates null, and string
concatenation treats it as empty text. `!print` consumes null without emitting any
bytes, including a newline. The REPL displays null stack entries as `null`; this is
a display label, not language keyword syntax. There is no null literal yet.

Strings currently contain literal text only: escapes, interpolation, smart quotes,
single quotes, and alternative delimiters are not implemented. Comments,
arrays, user functions, loops, and other arithmetic operators remain
unimplemented pending confirmed cases and design decisions.

## YAML behavior cases

```sh
swift run sigils spec                         # recursively reads Spec/TestCases
swift run sigils spec Spec/TestCases/01-scalars-on-the-stack.yml
swift run sigils spec path/to/cases another/case.yaml
```

Each nonempty YAML document is an independent case with an empty starting stack
and variable bindings:

```yaml
---
name: addition and output
code: |
  1 4 + !print
output: "5"
stack: []
```

Successful cases require `name`, `code`, `output`, and `stack`. An optional `commentary`
field is documentation only. Optional `confidence` is `low`, `medium`, or `high`.
Low-confidence cases are executed and asserted, but their behavioral failures do
not fail the suite or its exit status. Their results are marked non-blocking and
counted separately in the summary.
Medium/high cases and cases without confidence are enforced normally.
Malformed YAML or case schemas still fail, even at low confidence.
Null `output` means no output, and null `stack` means
an empty stack. Stack sequences are bottom-to-top and distinguish numbers from
strings; quote numeric-looking expected strings.

A null entry *inside* a stack sequence is a null value: `stack: [null]` expects one
entry, unlike `stack: []` or a null `stack` field, which expect no entries.

For ordinary scalar output, comparison ignores at most one final newline on each
side, never other whitespace. YAML block scalars (`|`, `|-`, `|+`, or `>`) compare
exactly after YAML's own folding/chomping, so they can assert precise newlines.
Expected output must be text or null; quote numeric output such as `"5"`.

An `error` field expects the first failure's category, not an exact diagnostic:

```yaml
name: detached destination
code: |
  8 ->x
  5 -> x
error: missing-attached-destination
stack: [5]
```

For error cases, `output` and `stack` are optional; if present they assert output
and data stack state at failure, before the REPL-only error value would be appended.
An unexpected, absent, or different error fails the case. Error categories currently
include `undefined-variable`, `missing-attached-destination`, `invalid-destination`,
`stack-underflow`, `type-error`, `syntax-error`, `numeric-overflow`, and `unknown-function`.
Index failures use `invalid-stack-index` or `stack-index-out-of-bounds`.
The structured error's line/column are tested in Swift; YAML location assertions
and error values inside expected stacks are not supported yet.

The runner discovers `.yml` and `.yaml` files recursively on every invocation,
deduplicates paths, and reports each case's file, document, name, and mismatches.
Empty documents from trailing `---` are ignored. Unknown/duplicate fields,
unsupported expected values, malformed YAML, unreadable paths, no cases, and failed
cases cause a nonzero exit. `swift test` also discovers the current repository
cases, without hardcoding their names or count.

The interpreter uses the Swift standard library; the CLI uses cross-platform
Foundation and [Yams](https://github.com/jpsim/Yams) for YAML. Terminal detection is
conditionally compiled for Unix and Windows. Builds, the current cases, and CLI
modes have been verified on macOS; Linux and Windows verification is still pending.

## Development rules

Run the existing behavior cases before adding features. If a case fails, fix the
implementation before expanding the language. Do not change cases to make code
pass; spec changes require explicit permission. Re-read the cases and `PLAN.md`
each development session, since either may be changed independently.

Confirm behavior decisions and deviations from the specs or brainstorming notes
before implementing them. `PLAN.md` records a suggested sequence, not a commitment.
