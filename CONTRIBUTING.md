# Contribute to Plastic

[AGENTS.md](AGENTS.md) holds the rules for working on this repository: intents, worktrees,
commits and releases. This page points to the rest.

| Read | For |
| ---- | --- |
| [docs/contributing/ARCHITECTURE.md](docs/contributing/ARCHITECTURE.md) | How the `plastic` command is built, and where the system architecture lives. |
| [docs/contributing/CODING_PRACTICES.md](docs/contributing/CODING_PRACTICES.md) | How Ruby is written, linted and scored here. |
| [docs/contributing/TECHNICAL.md](docs/contributing/TECHNICAL.md) | The gates, the byte budget and the test layout. |

## Test a change

Every test in this repository follows one of five patterns. Choose the pattern by what the code
under test touches, open the example and keep its shape.

| The code under test | Pattern | Built on | Example |
| --- | --- | --- | --- |
| A kernel class or a command, called inside the test's own process | Kernel test | `Plastic::TestCase` | `test/plastic/commands/intent_new_test.rb` |
| What a person gets from a command: the exit code and both output streams | Child process test | `Minitest::Test` with `KernelCommand` | `test/plastic/hooks/broken_store_test.rb` |
| `install.sh` or an installer script | Installer test | `Minitest::Test` with `InstallShHelper` | `test/install_sh_dependency_test.rb` |
| A behavior that reads best as a table of cases | Acceptance document | `varar/NAME.md` with `test/varar/NAME.steps.rb` | `varar/hook-resume.md` |
| A rule about the files of this repository | Guard test | `Minitest::Test` | `test/real_home_guard_test.rb` |

A test file has the path of its source file: `scripts/lib/plastic/commands/intent_new.rb` is
tested by `test/plastic/commands/intent_new_test.rb`.

### Rules for every test

1. Write the test first and commit it red.
1. Use a throwaway home. `Plastic::TestCase` gives one in `@home` and `@plastic_home`. A child
   process gets `HOME` and `PLASTIC_HOME` in the hash passed to it. No test reads or writes the
   real `~/.plastic` or `~/.claude`.
1. Pass the environment as a value. A test never assigns to `ENV`.
1. Use real SQLite files in the throwaway home, and read the rows back to check them.
1. Pass a collaborator in as an argument. Do not use a mocking library and do not replace a
   method on a live class.
1. Pass the time in. A test never calls `sleep` and never reads the clock to decide a result.
1. Stay on the machine: no network, no outside API and no key. To stand in for a program such
   as `curl`, put a fake program first on `PATH`.
1. Check what a person gets: the exit code, standard output and standard error. A command test
   checks all three.
1. Test one behavior in each test, and name the test as a sentence:
   `test_after_naming_a_missing_intent_fails_with_no_intent_written`.
1. Give a reason in words for every `skip`.
1. When code is deleted, delete its tests in the same change.

### Rules for a guard test

1. Read the subjects from the disk, and fail when the list of subjects is empty.
1. Test the detector on short sample text: one sample that it must catch and one that it must
   leave alone.
1. Before the commit, break the rule once on purpose and see the guard fail. Say so in the pull
   request description.

### Run the tests

```sh
ruby bin/test --only test/plastic/commands/intent_new_test.rb
bundle exec ruby bin/verify-change <base commit>
```

Run the test of each changed file once. Then run the gate once before the commit: it runs the
lint, the tests of the changed files with coverage, and the timing check. Do not run the full
suite on your machine. CI runs it.

## Add a command

1. Add one row to `scripts/lib/cli/table.rb`: the name, the file, the class and the help line.
2. Add one file under `scripts/lib/cli/commands/` with a `USAGE_LINE` and a public `call`.
3. Write the tests first and commit them red. Follow [Test a change](#test-a-change).
4. Run the gates once: `bundle exec ruby bin/verify-change <base commit>`.
5. Add the command to [README.md](README.md) and [docs/usage/FEATURES.md](docs/usage/FEATURES.md) in the same change.

## Cut a release

1. Bump the version in `package.json`.
2. Add or update the entry in `deprecations.yml` for anything this release removes or
   replaces.
3. Push the branch: `alpha`, `beta`, or `main`. The push is the release:
   `.github/workflows/publish.yml` creates the tag and the GitHub release for a version with
   no tag yet. The release carries the three files `install.sh` downloads.
4. Read [docs/release-lines.md](docs/release-lines.md) for the routing rule between the two
   lanes and the stable-line guarantees.
