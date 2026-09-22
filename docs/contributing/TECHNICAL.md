# Technical reference

The internals of the whole system are in [docs/internals.md](../internals.md). That page
moves into this slot when the scripts and tests that name its path change, in intent 372.
This page covers the tools around the `plastic` command.

## The gates

```bash
bundle exec ruby bin/verify-change <base commit>
```

`bin/verify-change` runs five steps on the lines changed since the base commit.

| Step | Passes when |
| ---- | ----------- |
| Lint | RuboCop reports no offense on the changed files. |
| Tests | The tests for the changed files pass. |
| Patch coverage | Every changed line and branch is covered. |
| Mutation | Mutineer kills the mutants on the changed code. |
| CRAP | No changed method scores above 30. |

Every step runs under a new `HOME` and `PLASTIC_TMP`. A mutant can turn an injected runner
into a live call, and the throwaway home keeps that call away from the real one.

Use the merge base with the target branch as the base commit. An older base makes the gate
measure lines that the branch did not change.

## The full suite

```bash
bin/test
```

Run it once per change, at the end. CI runs it on every push.

## The byte budget

`bin/plastic-bench` is the one script that measures every standing surface, the agent catalog
included. `test/context_budget_bench_test.rb` fails when a surface crosses its ceiling.

## Layout

| Path | Holds |
| ---- | ----- |
| `bin/plastic` | The launcher. |
| `scripts/lib/cli.rb` | The dispatcher. |
| `scripts/lib/cli/` | The shared classes. |
| `scripts/lib/cli/commands/` | One file per command. |
| `test/cli/` | One test file per class. |
| `test/varar/` | The acceptance documents. |
