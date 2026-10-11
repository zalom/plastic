# Tutorial: from a new intent to merged, delivered code

## What you will do

This tutorial takes one small change to a Ruby project from a new intent to a delivered
close. You create the intent, record a ruling, write the spec, plan the work graph, make the
change on a branch with a failing test first, have the work judged, merge the branch, and close
the intent as delivered. At the end, the intent sits under `## Completed` with the
`outcome.md` you wrote and a verification that passed.

The tutorial uses the guided path, which needs no hooks, no lock, and no agent team. Every
command here was run in a disposable `HOME` and `PLASTIC_HOME`. The output blocks come from
that run, and some are shortened. Paths, times, commit hashes, and lock names differ on your
machine: `/home/you` stands for your home directory.

Plastic records the work. It does not write the spec, the code, or the Git history for you.
Each step says who does it:

- **Plastic**: a `plastic` command.
- **You or your agent**: writing a file, running tests, or running Git.

## Before you start

- Plastic is installed. `plastic version` prints a version.
- Ruby and Git are on your `PATH`.
- To try the tutorial without touching your real stores, open a new shell, point `HOME` and
  `PLASTIC_HOME` at a scratch directory, and install there first. Type `exit` at the end to
  return to your normal `HOME`:

  ```sh
  bash
  export HOME=/tmp/plastic-tutorial/home
  export PLASTIC_HOME="$HOME/.plastic"
  export PATH="$HOME/.local/bin:$PATH"
  mkdir -p "$HOME/.claude"
  curl -fsSL https://raw.githubusercontent.com/zalom/plastic/main/install.sh | sh
  plastic install --claude
  hash -r
  command -v plastic
  ```

  The installer needs an existing `~/.claude` directory. It stops with `.claude not found`
  otherwise. It places the `plastic` command at `$PLASTIC_HOME/bin/plastic`, and
  `command -v plastic` must print that path. If it prints another path, the commands below
  would run your normal installation.
- In that shell, check that Ruby can load Minitest: `ruby -e 'require "minitest"'`. Some Ruby
  builds do not include it, and gems installed under your normal `HOME` may not be found from
  the scratch one. Run `gem install minitest` if the check fails.

## Create a small Ruby project

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

Add an `AGENTS.md` file at the repository root. `plastic install` registers only a
repository that has one. A line or two describing the project is enough.

Commit everything on `main`. A scratch `HOME` has no Git identity, so set one for this
repository first, with your own name and email:

```sh
git init -b main
git config user.name "Your Name"
git config user.email "you@example.com"
git add .
git commit -m "chore: greeter"
```

## Register the project

**Plastic.** From inside the repository, run:

```sh
plastic install --claude
```

`project new` creates the project store at `~/.plastic/stores/greeter/` and records the
repository path in `~/.plastic/projects.yml`. Every later command run inside this repository
resolves to the `greeter` store. From anywhere else, add `--project greeter`.

## Create the intent (What)

**Plastic.** Run:

```sh
plastic intent new "Let Greeter.greet take an optional greeting word"
```

The output names the new intent directory and the next step:

```text
intent: 1
printed store/1--let-greeter-greet-take-an-optional/intent.md
printed store/1--let-greeter-greet-take-an-optional/savepoint.md
printed store/1--let-greeter-greet-take-an-optional/graph.json
next: plastic intent spec 1 --project greeter
because: a new intent has no specification yet
```

The directory holds the intent file `intent.md`, placeholder files `spec.md`
and `outcome.md`, and empty `actions/` and `resources/` folders.
The intent is listed under `## Active` in `~/.plastic/stores/greeter/INDEX.md`.

## Record the rulings (Why)

**Plastic.** Run `plastic intent spec 1`. It prints the intent's state screen and the rules the
speccing conversation follows: one question at a time, two or three approaches with a
recommendation, and every ruling recorded the moment it lands.

**You and your agent** hold that conversation. When a ruling lands, record it:

```sh
plastic intent rule 1 "Keep the default greeting Hello so existing callers are unchanged"
```

The command prints one `appended:` line. The ruling is appended to the intent file's
`## Insights` section, stamped with the time, the `Why` stage, and the `human` author, followed
by the ruling text.

`intent rule` writes only to `## Insights`. If you keep a `### Decisions` list in the intent
file, write it yourself.

## Write the spec and plan the graph (How)

**You or your agent** write `spec.md` in the intent directory. No command writes it. It
replaces the placeholder that `intent new` created. Each done criterion carries a key in
square brackets, and the work graph ties every node to one key:

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
- [ ] [greeting] The new test passes and the old test still passes.
```

**Plastic.** Give the go-ahead, then add the nodes. The go-ahead is the owner's step, and
`plastic auto` refuses an intent without it:

```sh
plastic intent approve 1 --project greeter
plastic node add 1 "Add a failing test for the greeting keyword" --criterion greeting --project greeter
plastic node add 1 "Add the greeting keyword to Greeter.greet" --criterion greeting --project greeter
plastic edge add 1 N2 N1 --project greeter
```

`graph.json` in the intent directory is the checklist: the go-ahead, the verdicts, the nodes
with their criterion keys, and the edges. Plastic reprints it from the rows. `plastic graph
check 1` finds a done node with no findings, an isolated node, or a criterion no node covers.
`plastic intent show 1` lists the nodes and points at execution.

## Do the work (Exec)

**Plastic.** `plastic graph ready 1` lists the nodes ready to claim. Claim one, and Plastic
prints its brief:

```sh
plastic node claim 1 N1 --project greeter
```

**You or your agent** do the node on a branch:

```sh
git switch -c plastic/1--let-greeter-greet-take-an-optional
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

Commit the red test. Then record the findings, which marks the node done:

```sh
plastic node done 1 N1 "Test added and red: ArgumentError on the greeting keyword" --project greeter
```

Claim the second node. Change `lib/greeter.rb`:

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

Commit, and record the findings:

```sh
plastic node done 1 N2 "Greeter.greet takes greeting:, default Hello; both tests green" --project greeter
```

When a node cannot go on, `plastic node fail ID NODE TEXT` records why, `plastic node ask ID
NODE TEXT` puts a question to the owner, and `plastic node impede ID NODE TEXT` records an
impediment. `plastic node resolve ID NODE TEXT` reopens a node that waits on an answer.

To keep the commit on the record, write a session note. Replace `<sha>` with the commit
hash:

```sh
plastic session note "<sha> greeting keyword, tests green"
```

## Judge the work

**Plastic.** `plastic intent judge 1` prints the steps that start the judge. It takes no
options:

```sh
plastic intent judge 1 --project greeter
```

**The judge**, a reasoning agent, reads the spec, the nodes and their findings, and the
code. It records its verdict, with its findings as the text:

```sh
plastic intent verdict 1 accept "The new test and the old test pass; the default is unchanged." --project greeter
```

A `revise` verdict sends the agent back to add a fix node with `plastic node add`. A review
has two rounds, and a second `revise` is the owner's step: exit 3. An `accept` verdict that
is older than the newest change of a live node does not count.

## Write the outcome and merge the code (Git)

**You or your agent** replace the `outcome.md` placeholder in the intent directory. The shape
follows `templates/outcome.md`:

```markdown
---
disposition: delivered
---
# Outcome: Let Greeter.greet take an optional greeting word

## Summary
Greeter.greet takes an optional greeting word; the default stays Hello.

## Delivered
| Row | What |
| --- | --- |
| N1 | A test for the greeting keyword |
| N2 | The greeting keyword on Greeter.greet |

## Verification
- The new test passes and the old test still passes: `ruby -Ilib test/greeter_test.rb` printed 2 runs, 0 failures.

## Needs you
None

## Follow-ups
None
```

Plastic does not merge. The delivered close needs the `Merged:` and `Architecture map:`
bullets under Verification in outcome.md. With `review.pull_request` set to `required`, the
default, it also needs a `Pull request:` bullet and, once the person approves, an `Approved:`
bullet. A project that sets it to `off` skips those two.

**You.** Merge the branch and run the tests on `main`:

```sh
git switch main
git merge --no-ff plastic/1--let-greeter-greet-take-an-optional
ruby -Ilib test/greeter_test.rb
```

Add the bullets to `## Verification`, then store the file:

```markdown
- Merged: plastic/1--let-greeter-greet-take-an-optional into main at <commit>
- Architecture map: enola at <source revision>
```

```sh
plastic sync up --project greeter
```

## Close the intent as delivered

**Plastic.** Close the intent. The command takes no options:

```sh
plastic intent end 1 --project greeter
```

The close needs every live node done, every criterion covered, an accepted verdict that is
not older than the newest node change, and the `Verification` bullets you wrote in the outcome. When
something is missing, the command prints it and closes nothing. When everything holds, the
close writes the completion row with the judge verdict and the evidence built from the rows:
each criterion key with its done nodes and their findings. It releases the lock, prints the
intent's files, and hands the agent the wind-down steps: stop the processes and agents the
intent started.

`plastic intent show 1` shows the intent done:

```text
because: the intent is completed
```

`outcome.md` keeps what you wrote.

## The same change in auto mode

In auto mode, an agent team does the work from the rulings to the close. The commands below set up and inspect that
run. They do not run the team; your harness does that.

1. `plastic auto ID` refuses with exit 3 until `plastic intent approve ID` has written the
   go-ahead. Then it takes the delivery lock and names the code worktree at
   `<repo>/.claude/worktrees/ID--slug` on branch `plastic/ID--slug`. It prints both as rows;
   make the worktree at that path on that branch.

   ```text
   worktree: /home/you/greeter/.claude/worktrees/2--shout
   branch: plastic/2--shout

   next: plastic intent brief 2
   ```

   An intent with an open decision or no done criterion is refused with exit 3. Exit 3 means
   the step belongs to the owner: stop and report it.

2. `plastic intent brief ID` prints the preamble the dispatched agent reads first.
3. `plastic intent lock status ID` shows who holds the lock and where the worktree is.
4. `plastic help agent-architecture` names the steps the main session takes and the review
   rules it follows.
5. The close is the same `plastic intent end` as in the close above, with the same merge check.

`plastic intent end ID` refuses an intent that has no done criterion, no accepted verdict or
no merge record. An intent that will not ship closes with `plastic intent abandon`, which
takes no options. It hands over the revert steps until `outcome.md` holds a `Reverted:`
bullet under `## Verification`:

```sh
plastic intent abandon 2 --project greeter
```

The close sets the status to `abandoned`, with the disposition `superseded` when another
intent supersedes it and `cancelled` otherwise, and writes no completion row.

## Where to go next

- `plastic help track-1-guided`: the same cycle for a graph intent, driven one node at a time.
- `plastic help track-2-auto`: how the auto team walks the record.
- `plastic help completion-and-done`: what the close checks and writes.
- `plastic help locks-and-worktrees`: the delivery lock and the code worktree.
