# Tutorial: from a new intent to merged, delivered code

## What you will do

This tutorial takes one small change to a Ruby project from a new intent to a delivered
close. You create the intent, record a ruling, write the spec, plan, and checklist, make the
change on a branch with a failing test first, merge the branch, and close the intent as
delivered. At the end, the intent sits under `## Completed` with an `outcome.md` generated from
the record.

The tutorial uses the checklist path, which needs no hooks, no lock, and no agent team. Every
command here was run in a disposable `HOME` and `PLASTIC_HOME`. The output shown is the
output those runs printed.

Plastic records the work. It does not write the spec, the code, or the Git history for you.
Each step says who does it:

- **Plastic**: a `plastic` command.
- **You or your agent**: writing a file, running tests, or running Git.

## Before you start

- Plastic is installed. `plastic version` prints a version.
- Ruby and Git are on your `PATH`.
- To try the tutorial without touching your real stores, point `HOME` and `PLASTIC_HOME` at a
  scratch directory and install there first:

  ```sh
  export HOME=/tmp/plastic-tutorial/home
  export PLASTIC_HOME="$HOME/.plastic"
  mkdir -p "$HOME/.claude"
  npx -y @zalom/plastic install --claude
  ```

  The installer needs an existing `~/.claude` directory. It stops with `.claude not found`
  otherwise.

## 1. Create a small Ruby project

**You.** Create a Git repository named `greeter` with one method and one test:

```ruby
# lib/greeter.rb
# frozen_string_literal: true

module Greeter
  def self.greet(name)
    "Hello, #{name}!"
  end
end
```

```ruby
# test/greeter_test.rb
# frozen_string_literal: true

require "minitest/autorun"
require "greeter"

class GreeterTest < Minitest::Test
  def test_greets_by_name
    assert_equal "Hello, Ada!", Greeter.greet("Ada")
  end
end
```

Add an `AGENTS.md` file at the repository root. `plastic project new` refuses to register a
repository without one. A line or two describing the project is enough.

Commit everything on `main`:

```sh
git init -b main
git add .
git commit -m "chore: greeter"
```

## 2. Register the project

**Plastic.** From inside the repository, run:

```sh
plastic project new greeter --path "$PWD"
plastic project links
```

`project new` creates the project store at `~/.plastic/stores/greeter/` and records the
repository path in `~/.plastic/projects.yml`. Every later command run inside this repository
resolves to the `greeter` store. From anywhere else, add `--project greeter`.

## 3. Create the intent (What)

**Plastic.** Run:

```sh
plastic intent new "Let Greeter.greet take an optional greeting word" --slug custom-greeting
```

The output names the new intent directory and the next step:

```text
/home/you/.plastic/stores/greeter/store/1--custom-greeting
next: plastic intent spec 1 --project greeter
because: a new intent has no specification yet
```

The directory holds the intent file `1--custom-greeting.md`, placeholder files `spec.md`,
`plan.md`, `checklist.md`, and `outcome.md`, and empty `actions/` and `resources/` folders.
The intent is listed under `## Active` in `~/.plastic/stores/greeter/INDEX.md`.

## 4. Record the rulings (Why)

**Plastic.** Run `plastic intent spec 1`. It prints the intent's state screen and the rules the
speccing conversation follows: one question at a time, two or three approaches with a
recommendation, and every ruling recorded the moment it lands.

**You and your agent** hold that conversation. When a ruling lands, record it:

```sh
plastic intent rule 1 "Keep the default greeting Hello so existing callers are unchanged"
```

The ruling is appended to the intent file's `## Insights` section, stamped with the time, the
`Why` stage, and the `human` author:

```text
appended: 2026-09-23T10:32:15Z · Why · human — Keep the default greeting Hello so existing callers are unchanged
```

`intent rule` writes only to `## Insights`. If you keep a `### Decisions` list in the intent
file, write it yourself.

## 5. Write the spec, the plan, and the checklist (How)

**You or your agent** write three files in the intent directory. No command writes them. Each
file replaces the placeholder that `intent new` created.

`spec.md` states the accepted scope:

```markdown
# Spec: Optional greeting word

## Problem
`Greeter.greet` always says "Hello". Callers cannot choose another greeting.

## Goals
- `Greeter.greet("Ada", greeting: "Hi")` returns "Hi, Ada!".

## Non-Goals
- Translation.

## Approach
Add a keyword argument with the default "Hello".

## Decisions
- The default stays "Hello", so existing callers are unchanged.

## Acceptance Criteria
- [ ] The new test passes and the old test still passes.
```

`plan.md` follows `templates/plan.md`: a `## Goal`, the `## Steps`, and `## Notes`.
`checklist.md` follows `templates/checklist.md`, with one checkbox for each piece of work:

```markdown
# Checklist: Optional greeting word

## In Progress
- [ ] Add a failing test for the greeting keyword
- [ ] Add the greeting keyword to Greeter.greet

## Completed
(move items here when done)
```

**Plastic.** `plastic intent show 1` now reads the checklist and points at execution:

```text
| S1 | open | Add a failing test for the greeting keyword |
| S2 | open | Add the greeting keyword to Greeter.greet |
next: plastic intent step 1 --project greeter
because: the checklist has unfinished work
```

Until `spec.md` is written, the same screen points back at `plastic intent spec 1`. Until
`plan.md` and `checklist.md` are written, it says so in the `because:` line.

## 6. Do the work (Exec)

**Plastic.** `plastic intent step 1` prints the next unchecked item. On a checklist intent, it
does not run anything:

```text
work       Add a failing test for the greeting keyword
checklist  /home/you/.plastic/stores/greeter/store/1--custom-greeting/checklist.md

next: none
because: perform this checklist item, record its verification, then run plastic intent show 1 --project greeter
```

**You or your agent** do the item on a branch. The branch name `plastic/1--custom-greeting`
matches the name `plastic auto take` would provision, so the close can find it:

```sh
git switch -c plastic/1--custom-greeting
```

Add the new test to `test/greeter_test.rb`:

```ruby
def test_takes_a_greeting_word
  assert_equal "Hi, Ada!", Greeter.greet("Ada", greeting: "Hi")
end
```

Run the tests and watch the new one fail:

```sh
ruby -Ilib test/greeter_test.rb
```

```text
ArgumentError: wrong number of arguments (given 2, expected 1)
2 runs, 1 assertions, 0 failures, 1 errors, 0 skips
```

Commit the red test. Then tick the item in `checklist.md`: change `- [ ]` to `- [x]`, in the same
commit as the work when the checklist lives in the repository, or right after it otherwise.

Run `plastic intent step 1` again for the second item. Change `lib/greeter.rb`:

```ruby
module Greeter
  def self.greet(name, greeting: "Hello")
    "#{greeting}, #{name}!"
  end
end
```

Run the tests again. Both pass:

```text
2 runs, 2 assertions, 0 failures, 0 errors, 0 skips
```

Commit, and tick the second item. `plastic intent show 1` now points at
`plastic intent verify 1`, because every checklist item is complete.

To keep the commit on the record, add a note to the savepoint:

```sh
plastic intent note 1 "<sha> greeting keyword, tests green" --kind Commit
```

## 7. Verify

**Plastic.** Run `plastic intent verify 1`. It runs the per-intent doctor check, the em-dash
guard, and a diffstat of the code branch against `main`.

Before the close, the doctor check fails on this checklist intent, and the command exits 1:

```text
doctor: FAIL intent_lifecycle_artifacts: 1 lifecycle-artifact gap(s)
em-dash guard: pass (0 violations)
diffstat against main:
 lib/greeter.rb       | 4 ++--
 test/greeter_test.rb | 4 ++++
 2 files changed, 6 insertions(+), 2 deletions(-)
plastic: verify-intent exited 2
```

The gap is `outcome.md`, which is still a placeholder. `plastic intent end` generates it at
the close, so this failure is expected at this point. Read the diffstat and the em-dash
result, and go on.

## 8. Merge the code (Git)

Plastic does not merge. Its delivered close refuses code that is not merged.

**Plastic.** Try the close while the repository is still on the code branch:

```sh
plastic intent end 1 --delivered --summary "Greeter.greet takes an optional greeting word; the default stays Hello."
```

It exits 1 and writes nothing:

```text
end-intent: refusing a delivered close: the repo checkout /home/you/greeter is on the code branch plastic/1--custom-greeting itself, so the code is not merged anywhere. Check out the branch you release from, merge plastic/1--custom-greeting into it, then run the close again
end-intent: nothing was merged, written, or released
```

**You.** Merge the branch and run the tests on `main`:

```sh
git switch main
git merge --no-ff plastic/1--custom-greeting
ruby -Ilib test/greeter_test.rb
```

## 9. Close the intent as delivered

**Plastic.** Preview the close first:

```sh
plastic intent end 1 --delivered --summary "Greeter.greet takes an optional greeting word; the default stays Hello." --dry-run
```

The dry run lists what the close would do: move the `INDEX.md` entry to `## Completed`, append
the terminal savepoint line, commit the store repository, and release the lock and the code
worktree. It ends with:

```text
next: none
because: the dry run wrote nothing and found nothing that would refuse the close
```

Run the same command without `--dry-run`. The close fills the records that are still
placeholders from the record itself:

```text
end-intent: backfilled actions/ACTION_1.md from the record
end-intent: backfilled outcome.md from the record
```

`plastic intent show 1` now shows both steps done:

```text
next: none
because: the intent is completed
```

Read `outcome.md` in the intent directory. Its Summary is the `--summary` text you gave.

## The same change in auto mode

In auto mode, an agent team does steps 4 to 9. The commands below set up and inspect that
run. They do not run the team; your harness does that.

1. `plastic auto take ID` takes the delivery lock and provisions the code worktree at
   `<repo>/.claude/worktrees/ID--slug` on branch `plastic/ID--slug`.

   ```text
   intent    2--shout
   lock      acquired by auto-9184f6c4fa, auto mode
   worktree  /home/you/greeter/.claude/worktrees/2--shout
   ```

   Run from inside a conversation session, `auto take` refuses with exit 3 unless you pass
   `--allow-inline`. Exit 3 means the step belongs to the owner: stop and report it.

2. `plastic auto brief ID` prints the preamble the dispatched agent reads first.
3. `plastic auto lock status ID` shows who holds the lock and where the worktree is.
4. `plastic auto report ID` prints the report contract and the review rules the lead follows.
5. The close is the same `plastic intent end` as in step 9, with the same merge check.

`plastic intent end ID --delivered` refuses an intent that nobody worked on. The spec, plan,
checklist, and outcome are still placeholders, and the worktree has no changes. Close it with
`--abandoned` instead:

```sh
plastic intent end 2 --abandoned --summary "Probe of the auto contract only."
```

The abandoned close also removes the code worktree.

## Where to go next

- `plastic help track-1-guided`: the same cycle for a graph intent, driven one node at a time.
- `plastic help track-2-auto`: how the auto team walks the record.
- `plastic help completion-and-done`: what the close checks and writes.
- `plastic help locks-and-worktrees`: the delivery lock and the code worktree.
