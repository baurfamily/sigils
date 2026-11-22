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
printf '1 + 4 !print\n' | swift run sigils
swift run sigils spec
swift test
```

The executable is also available at `.build/debug/sigils`. `sigils program.sigils`
and `sigils -` are shortcuts for file and STDIN execution. With no arguments, a
terminal starts the REPL; redirected input executes as one program.

The REPL retains its stack between lines and displays it bottom-to-top after each
successful line. EOF (usually Ctrl-D on Unix) exits. Files and STDIN start with an
empty stack and emit only explicitly printed output. Errors go to STDERR and
noninteractive execution exits unsuccessfully. A failed execution does not commit
stack changes or buffered output; REPL errors leave the previous stack intact.

## Supported language

| Syntax | Behavior |
| --- | --- |
| `5`, `12.2`, `-8`, `0.1` | Push a number onto the stack. |
| `"hello, world"` | Push a single-line, double-quoted string. |
| `1 + 4` | Push `1`; `+` consumes the stack's top number and the following numeric literal, pushing their sum. |
| `"hello" !print` | Consume the top value and print it with a newline. |
| Spaces and newlines | Separate instructions; `1+4` also works. |

Addition leaves deeper stack entries untouched. `+ 4` can therefore operate on a
number left by an earlier REPL line. Type mismatches, missing operands, unsupported
syntax, and unknown functions are errors with line/column locations.

Numbers currently use finite IEEE-754 `Double` values. Decimal arithmetic may round,
and integers beyond 2^53 are not all exactly representable. Whole-number output omits
the `.0` suffix. Numeric equality in specs is exact, not tolerance-based.

Strings currently contain literal text only: escapes, interpolation, smart quotes,
single quotes, and alternative delimiters are not implemented. Variables, comments,
arrays, user functions, loops, other operators, and stack-access symbols remain
unimplemented pending confirmed cases and design decisions.

## YAML behavior cases

```sh
swift run sigils spec                         # recursively reads Spec/TestCases
swift run sigils spec Spec/TestCases/01-scalars-on-the-stack.yml
swift run sigils spec path/to/cases another/case.yaml
```

Each nonempty YAML document is an independent case with an empty starting stack:

```yaml
---
name: addition and output
code: |
  1 + 4 !print
output: "5"
stack: []
```

Required fields are `name`, `code`, `output`, and `stack`. An optional `commentary`
field is documentation only. Null `output` means no output, and null `stack` means
an empty stack. Stack sequences are bottom-to-top and distinguish numbers from
strings; quote numeric-looking expected strings.

For ordinary scalar output, comparison ignores at most one final newline on each
side, never other whitespace. YAML block scalars (`|`, `|-`, `|+`, or `>`) compare
exactly after YAML's own folding/chomping, so they can assert precise newlines.
Expected output must be text or null; quote numeric output such as `"5"`.

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
