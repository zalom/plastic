# Technical reference

The internals of the whole system are in [docs/internals.md](../internals.md). This page
covers the tools around the `plastic` command.

## The gates

```bash
bundle exec ruby bin/verify-change <base commit>
```

`bin/verify-change` checks only the lines changed since the base commit. The following block
shows its steps in order.

```text
bin/verify-change origin/alpha
  find the merge base with origin/alpha
  list the changed files
    the Ruby sources under scripts/, lib/, tools/ or bin/lib/
    the tests for those sources, and every changed test
  stop with exit 1 when a changed source has no test file
  make a throwaway HOME and PLASTIC_TMP for every step below
  Lint              RuboCop on every changed Ruby file
  Tests             the tests for the changed files, with coverage on
    red tests stop the gate here, because a failing test kills every mutant
  Patch coverage    every changed line and branch
  Mutation testing  Mutineer on the changed lines
  CRAP scores       each changed method
  Code smells       Reek on the changed sources, with .reek.yml
  RubyCritic score  the changed sources that no todo list names
  print "Change verified", or the names of the steps that failed
exit code 0 verified, 1 a check failed, 2 a usage or git error
```

The following table says when each step passes.

| Step | Passes when |
| ---- | ----------- |
| Lint | RuboCop reports no offense on the changed files. |
| Tests | The tests for the changed files pass. |
| Patch coverage | Every changed line and branch is covered. |
| Mutation testing | Mutineer kills at least 75 percent of the mutants on the changed code. |
| CRAP scores | No changed method scores above 30. |
| Code smells | Reek finds no smell in the changed sources. |
| RubyCritic score | The changed sources that no todo list names score 90 or more out of 100. |

A lint failure does not stop the other steps. Only red tests stop the gate early.

Lint reads `.rubocop_with_todo.yml`. It is `.rubocop.yml` plus `.rubocop_todo.yml`, the
generated list of offenses in code written before 2026-09-30. So a lint run reports what the
change did and nothing else. Reek reads `.reek.yml` the same way: its exclude lists hold only
the smells of that older code. RubyCritic runs Reek, Flay and Flog, and scores the changed
sources from their smells, duplication and complexity. It leaves out a file that
`.rubocop_todo.yml` or `.reek.yml` lists, because that file is older code, and it prints the
names it left out. When every changed source is older code, the step does not run.

Every step runs under a new `HOME` and `PLASTIC_TMP`. A mutant can turn an injected runner
into a live call, and the throwaway home keeps that call away from the real one.

Use the merge base with the target branch as the base commit. An older base makes the gate
measure lines that the branch did not change. For a branch of `alpha`, the base is
`origin/alpha`.

## The tests

Run only the changed files' tests, once each; the full suite is never run locally, CI runs it.

```bash
ruby bin/test --only test/plastic/routine_test.rb
```

CI runs the full suite on every push to `main` and `alpha`, and on every pull request
into them. `bin/test` with no argument is the command CI runs.

On a full run, `bin/test` splits the test files in two. It runs the kernel tests under
`test/plastic/` in a process of their own first, then every other test file in its own
process. The kernel defines some of the same constant names as the live command line, so the
two cannot load into one process. The run fails when either process fails. The split ends when
the live command line retires.

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
| `scripts/lib/plastic.rb` | The entry of the tri-graph kernel. |
| `scripts/lib/plastic/` | The kernel: its command line, routines, workflows, end values and graph layer. |
| `test/plastic/` | The kernel tests, which run in their own process. |
| `docs/resources/` | The figures of these pages and the Ruby scripts that draw them. |
| `varar/` | The acceptance documents. |
| `test/varar/` | The step files for the acceptance documents. |
