# Technical reference

The internals of the whole system are in [docs/internals.md](../internals.md). This page
covers the tools around the `plastic` command.

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
| Mutation | Mutineer kills at least 75 percent of the mutants on the changed code. |
| CRAP | No changed method scores above 30. |

Every step runs under a new `HOME` and `PLASTIC_TMP`. A mutant can turn an injected runner
into a live call, and the throwaway home keeps that call away from the real one.

Use the merge base with the target branch as the base commit. An older base makes the gate
measure lines that the branch did not change.

## The full suite

```bash
bin/test
```

Run it once per pull request, just before the pull request opens. CI runs it on every push to
`main` and `alpha` and on every pull request into them.

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
| `test/cli/` | The tests for the dispatcher, the shared classes and the commands. |
| `varar/` | The acceptance documents. |
| `test/varar/` | The step files for the acceptance documents. |
