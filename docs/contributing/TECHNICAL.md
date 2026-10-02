# Technical reference

The internals of the whole system are in [docs/internals.md](../internals.md). This page
covers the tools around the `plastic` command.

## The gates

```bash
bundle exec ruby bin/verify-change <base commit>
```

`bin/verify-change` checks only the lines changed since the base commit.

It finds the merge base, lists the changed Ruby sources under `scripts/`, `lib/`, `tools/`
and `bin/lib/` with their tests, and stops with exit 1 when a changed source has no test file.
In a throwaway home it then runs the steps of the following table in order. Red tests stop the
gate at the second step, because a failing test kills every mutant. It prints "Change
verified" or the names of the failed steps, and exits 0 verified, 1 a check failed, or 2 a
usage or git error.

The following table says when each step passes.

| Step | Passes when |
| ---- | ----------- |
| Lint | RuboCop reports no offense on the changed files. |
| Tests | The tests for the changed files pass. |
| Timing check | Every test file ran under 5 seconds and every Varar document under 10, on a re-run when the first run went over. |
| Patch coverage | Every changed line and branch is covered. |
| Mutation testing | Every mutant on the changed code has a verdict, and killed mutants are at least 75 percent of the total. |
| CRAP scores | No changed method scores above 30. |
| Code smells | Reek finds no smell in the changed sources. |
| RubyCritic score | The changed sources that no todo list names score 90 or more out of 100. |

A lint failure does not stop the other steps. Only red tests stop the gate early.

The Tests step loads `bin/lib/test_timings.rb`, a Minitest extension that sums each test's
time into a file under the sandbox `PLASTIC_TMP`, booking a Varar document's tests to the
document (read from `varar.config.json`) rather than to the gem file that defines them. The
Timing check step then reads that file: a file or document over its cap is re-run alone
before it is called red, and the gate prints both times either way. RSpec projects, and
Minitest run through `bin/rails test`, have no step to load the extension into, so the gate
skips the Timing check for them and says so.

Coverage starts before the timing extension loads. A timing rerun must succeed;
a fast failure cannot pass the cap. A Varar rerun selects the named document's
generated test class, so other documents do not count toward its time.

The Mutation testing step runs `bin/lib/mutation_verdicts.rb`, which removes any report left
under the sandbox `PLASTIC_TMP` from an earlier run, runs Mutineer with `--format json
--output` into that same path, and reads only what this run wrote. A mutant Mutineer could not
give a verdict is re-run alone, one subject at a time with `--only NAME --jobs 1` and the same
sources and tests, and the gate prints each re-run's subject and seconds. A mutant still
without a verdict after its re-run fails the step by name; a mutant with no subject to isolate
(a failure before a worker forked) fails at once, with no re-run.

Reruns must exit successfully and write a report. Each resolved verdict needs the
mutant's id in an explicit result list. Mutineer 1.0 reports killed mutants only
as a total, so a rerun cannot prove an individual kill from that format. Such an
id stays unresolved and fails the gate; missing or uncovered ids never count as kills.

Lint reads `.rubocop_with_todo.yml`. It is `.rubocop.yml` plus `.rubocop_todo.yml`, the
generated list of offenses in code written before 2026-09-30. So a lint run reports what the
change did and nothing else. Reek reads `.reek.yml` the same way: its exclude lists hold only
the smells of that older code. RubyCritic runs Reek, Flay and Flog, and scores the changed
sources from their smells, duplication and complexity. It leaves out a file that
`.rubocop_todo.yml` or `.reek.yml` lists, because that file is older code, and it prints the
names it left out. When every changed source is older code, the step does not run.

Every step runs under a new `HOME` and `PLASTIC_TMP`. A mutant can turn an injected runner
into a live call, and the throwaway home keeps that call away from the real one. The timings
file the Tests step writes and the mutation report Mutineer writes both live under that same
`PLASTIC_TMP`, so a mutant that reaches for either file finds only the throwaway copy.

Use the merge base with the target branch as the base commit. An older base makes the gate
measure lines that the branch did not change. For a branch of `alpha`, the base is
`origin/alpha`.

## The tests

Run only the changed files' tests, once each; the full suite is never run locally, CI runs it.

```bash
ruby bin/test --only test/plastic/routine_test.rb
```

CI runs the full suite on every push to `main` and `alpha`, and on every pull request
into them. It runs `bin/test` with no argument for the unit layer, then `bin/test --system` for
the acceptance documents, the way `rails test` and `rails test:system` split them.

On a full run, `bin/test` splits the test files in two. It runs the kernel tests under
`test/plastic/` in a process of their own first, then every other test file in its own
process. The kernel defines some of the same constant names as the live command line, so the
two cannot load into one process. The run fails when either process fails. The split ends when
the live command line retires.

The kernel has two layers of tests:

- **Unit tests** under `test/plastic/` call public methods only. Each class inherits
`Plastic::TestCase` from `test/test_helper.rb`, as Rails tests inherit one base class. Each
process builds one home per fixture under `test/fixtures/homes/` and opens its databases
once. Every test runs inside a transaction on each of those databases and rolls it back in
teardown, as Rails does with transactional tests. Teardown also resets the home's other
files: it compares each file's type, size, mode, link target and change time against a
snapshot taken when the home was built, and touches only what a test changed, instead of
copying the whole fixture back every time. A restored file's new state is recorded, so a later
test that leaves it alone does not pay to have it restored again. It never follows a symlink,
so a link a test made to a folder outside the home never carries the reset into that folder; a
tracked database and its rollback journal are left to the transaction rollback instead of this
file comparison. Teardown also closes any database the test opened. The tests run the real
`Graph::Database` through the `sqlite3` gem, so each one reads and writes the state the
commands would.
- **Acceptance documents** under `varar/` run each command of the storage kernel in a child
  Ruby process, against a fresh home. The steps read the rows back through the `sqlite3`
  gem, on a connection of their own. `bin/plastic` routes to the kernel (intent 397), so the
  steps call it either through the packaged executable or the kernel's own command line
  directly, by the case. `bin/test --system` runs them through `test/varar_test.rb`. The change
  gate never passes that file to the mutation run.

## The byte budget

`bin/plastic-bench` is the one script that measures every standing surface, the agent catalog
included. `test/context_budget_bench_test.rb` fails when a surface crosses its ceiling.

## Layout

| Path | Holds |
| ---- | ----- |
| `bin/plastic` | The launcher; points at the kernel (intent 397). |
| `scripts/lib/plastic.rb` | The entry of the tri-graph kernel. |
| `scripts/lib/plastic/` | The kernel: its command line, routines, workflows, end values and graph layer. |
| `scripts/lib/plastic/cli.rb` | The dispatcher. |
| `scripts/lib/plastic/cli/` | The shared classes. |
| `scripts/lib/plastic/commands/` | One file per command. |
| `scripts/lib/plastic/graph/` | The kernel's graph layer: the store databases, the printed files and sync. |
| `test/plastic/` | The kernel tests, which run in their own process. |
| `test/cli/` | The acceptance test of the packaged executable, `bin/plastic`, run as installed. |
| `test/test_helper.rb` | The boot of every test, and `Plastic::TestCase`, the base class of the kernel tests. |
| `test/test_helpers/` | The helpers `Plastic::TestCase` includes, and the builder of the home fixtures. |
| `test/fixtures/homes/` | The homes the kernel tests start from, one file each. |
| `test/fixtures/routines.rb` | The routines, workflows and hooks that exist only for the kernel tests. |
| `test/fixtures/legacy_store/` | A copy of a store written before `store/index.json`, for the import tests. |
| `docs/resources/` | The figures of these pages, copied from the tri-graph proposal pages. |
| `varar/` | The acceptance documents. |
| `test/varar/` | The step files for the acceptance documents. |
| `test/varar/support/kernel_command.rb` | Runs the kernel's command line in a child process for the storage documents. |
