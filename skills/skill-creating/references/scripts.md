# Scripts: when deterministic code beats prose

Decide whether a skill ships a script, and write scripts that hold their determinism.
Read this when choosing script versus prose, or when writing a script that ships with a
skill.

For which bucket holds a given piece of content (scripts versus references versus
assets), read `references/progressive-disclosure.md`. This file covers only the
script-or-prose decision and script discipline.

## Contents

- [Ship a script or write prose](#ship-a-script-or-write-prose)
- [The three-way test](#the-three-way-test)
- [Make scripts solve, not punt](#make-scripts-solve-not-punt)
- [Test by running](#test-by-running)
- [Match freedom to fragility](#match-freedom-to-fragility)
- [Wire validators into hooks](#wire-validators-into-hooks)
- [Script hard requirements](#script-hard-requirements)
- [Plastic conventions](#plastic-conventions)
- [Worked example](#worked-example)
- [Self-check](#self-check)

## Ship a script or write prose

Ship a script when either condition holds:

1. The same code gets rewritten on every run.
2. Deterministic reliability matters (one wrong character breaks the result).

Otherwise write prose. A script is executed, not loaded, so its body stays out of
context and costs no tokens at trigger time. The price is an indirection: the agent must
find the script, learn its interface, and run it. Pay that price only when repetition or
determinism earns it. [G1]

## The three-way test

When something repeats, route it by what repeats, not by gut feel. [G2]

| What repeats | Bucket | Why |
| --- | --- | --- |
| Identical code | `scripts/` | Run it; do not regenerate it each time. |
| Identical boilerplate output | `assets/` (template) | Copy the template into output; never read it into context. |
| Re-discovered facts | `references/` | Read it once, on the trigger that needs it. |

A symptom of the wrong choice: an agent pasting the same 30 lines of Ruby across three
runs belongs in `scripts/`, not in prose; a fixed file header the agent retypes belongs
in `assets/`; a constant the agent keeps looking up belongs in `references/`.

## Make scripts solve, not punt

A script that hands its failure back to the agent loses the determinism that justified
shipping it. [G3]

- Handle errors inside the script. Catch the failure, print a clear diagnostic to stderr,
  and exit non-zero. Do not raise a raw stack trace and leave the agent to interpret it.
- No voodoo constants. Every magic number, path, or threshold gets a name and a comment
  stating where it came from. An unexplained `0.87` is a future break.
- State the mode. Say explicitly whether the agent executes the script or reads it. A
  validator is executed; a snippet meant to be copied is read. Ambiguity makes the agent
  guess.

## Test by running

An untested script is a latent break. Run it against real input before shipping. [G4]

- Exercise the success path and at least one failure path; confirm the exit code and the
  stderr message.
- Delete any example or scratch files the run generated that the skill does not ship.
  Stray files are clutter and may load by accident.

## Match freedom to fragility

Match degrees of freedom to fragility. Put guardrails on the narrow bridge, not the open
field. [G6]

| Task shape | Form | Reason |
| --- | --- | --- |
| Open, judgment-heavy | Prose | The agent needs room to adapt; code would over-constrain. |
| A preferred, repeatable pattern | Parameterized script (flags/env) | One correct shape, with controlled variation. |
| Fragile or destructive sequence | Fixed "do not modify" script | One exact path; any edit risks data loss. |

Mark a fragile script as "do not modify" in its `--help` and in the pointer that sends the
agent to it. For side-effecting workflows, gate execution behind a validator (see below)
rather than trusting the agent to check preconditions by hand.

## Wire validators into hooks

When a rule must hold every time, wire a deterministic validator into a hook rather than
restating the rule in prose. [G5]

- A `PreToolUse` validator can refuse an action before it runs; a packaging step can
  refuse to ship a skill that fails validation.
- Gate destructive steps behind validate-then-act: the validator passes, then the action
  runs. A prose reminder ("remember to check X first") is probabilistic; a hook is not.

For hook event selection, exit-code semantics, and path conventions, read
`references/hooks.md`.

## Script hard requirements

Every script that ships with a skill meets these, because an agent runs it unattended:

1. No interactive prompts. A blocking `gets` or `read -p` hangs the agent forever. Take
   all input up front.
2. Input via flags, environment variables, or stdin. Never mid-run questions.
3. `--help` is the primary documentation. Describe purpose, every flag, input, output, and
   exit codes there, so the agent learns the interface without reading the source.
4. Structured output. Data on stdout, diagnostics and progress on stderr, so the caller
   can capture one without the other.
5. Idempotent operations. Running twice produces the same end state; re-running after a
   partial failure is safe.
6. Meaningful, documented exit codes. 0 for success, distinct non-zero codes for distinct
   failures, each named in `--help`.

## Plastic conventions

- Scripts ship in Ruby. A worked example that shows a script shows Ruby.
- Any shell script runs under macOS `/bin/bash` 3.2. No `bash` 4.x features (no
  associative arrays, no `mapfile`, no `${var^^}`), and no heredocs inside `$(...)`.

## Worked example

A skill validates that an intent slug is well formed before any directory is created. The
check runs on every intent and must be exact, so it ships as a script, not prose. [G1][G3]

`scripts/validate_slug.rb`:

```ruby
#!/usr/bin/env ruby
# Validate an intent slug. Execute this; do not inline its logic.
# Usage: validate_slug.rb SLUG
# Exit: 0 valid, 1 malformed, 2 wrong argument count.

# Convention source: A5 of the best-practices standard (lowercase,
# digits, single hyphens, no leading/trailing/consecutive hyphens).
SLUG_PATTERN = /\A[a-z0-9]+(-[a-z0-9]+)*\z/

if ARGV.length != 1
  warn "usage: validate_slug.rb SLUG"
  exit 2
end

slug = ARGV.fetch(0)
if SLUG_PATTERN.match?(slug)
  puts slug            # data on stdout
  exit 0
else
  warn "malformed slug: #{slug.inspect}" # diagnostic on stderr
  exit 1
end
```

This script earns its place: identical code on every run, one exact rule, errors handled
inside, the named constant cites its source, data on stdout and diagnostics on stderr,
documented exit codes, and the header states it is executed. An open task ("name this
intent well") would stay prose; this fixed check is a script.

## Self-check

- Does this code repeat or demand exactness? If not, it stays prose. [G1]
- Did the right bucket win the three-way test? [G2]
- Are errors handled inside, constants named, and the execute-or-read mode stated? [G3]
- Did the script run green on a success path and a failure path, with scratch files
  removed? [G4]
- Does fragility match form, with destructive steps gated by a validator? [G5][G6]
