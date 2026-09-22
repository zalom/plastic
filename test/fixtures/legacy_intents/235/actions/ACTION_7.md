# ACTION_7: fix the install docs and confirm the Ruby floor is unchanged

Intent: 235, Make the first install work on a clean Mac.
Satisfies: AC1. Preserves AC3, AC10.

## Context you need (do not go looking for it)

`README.md` currently tells a new user that Ruby is "already on macOS and Linux". On a clean Mac
that is misleading. macOS ships Ruby 2.6.10, and Plastic's floor is 3.0.0, so the user hits a
refusal at the very first command with no warning from the docs. The whole point of this intent
is to make the first install honest, and the requirements line is part of that surface.

The floor itself does NOT change. `Preflight::RUBY_FLOOR` stays `"3.0.0"`. This action confirms
that with evidence rather than editing anything.

## Where you work

Worktree root:
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac`

If Edit or Write is denied or writes to the wrong tree, fall back to a Bash ruby write with
absolute paths and ` # plastic-ok` appended.

## Step 1: fix the requirements line in `README.md`

File: `<worktree>/README.md`, line 163.

BEFORE:
```
Plastic needs Ruby (already on macOS and Linux) and Node.js 18 or later. Bun
users can run `bunx` in place of `npx`; Bun is never required.
```

AFTER:
```
Plastic needs Ruby 3.0 or later and Node.js 18 or later. Most Linux systems already
have a new enough Ruby. macOS ships Ruby 2.6, which is too old, so a clean Mac needs
a newer one first:

```
curl https://mise.run | sh        # only if mise is not installed yet
mise use --global ruby@3.3
```

The installer checks this before it does anything and tells you the same thing if the
Ruby it finds is too old. Bun users can run `bunx` in place of `npx`; Bun is never
required.
```

Watch the nesting: the block above contains a fenced code block. Write it into `README.md` as a
real fenced block, not as nested backticks inside another fence.

`README.md` is user-facing, so no em-dash, no en-dash, and no AI tell-tale phrasing. Plain short
sentences. The wording above already meets that.

This is documentation telling the user what to run. It is NOT an auto-install code path, so AC3
is preserved. Do not add any code anywhere that runs `curl https://mise.run`, `mise use` or
`mise install` on the user's behalf.

## Step 2: check for any other stale requirement claim

```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac
grep -rn "already on macOS\|Node.js 18\|needs Ruby" README.md docs/ skills/ 2>/dev/null
```

The only known hit is the README line you just fixed. If the grep surfaces another place that
claims Ruby is already present or omits the version, fix it the same way. If it surfaces nothing
else, that is the expected result and there is nothing more to do here.

Do NOT edit `docs/reviews/`. Those are dated historical review records, not live documentation.

## Step 3: confirm the floor is unchanged (AC1)

Three pieces of evidence, all read-only.

1. The constant is still 3.0.0:

```
grep -n 'RUBY_FLOOR' scripts/lib/preflight.rb
```

Must show `RUBY_FLOOR = "3.0.0"`.

2. The file has zero changed lines in this intent's diff:

```
git -C /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac diff --name-only main...HEAD -- scripts/lib/preflight.rb
git -C /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac diff --name-only -- scripts/lib/preflight.rb
```

Both must print nothing.

3. The guard tests still assert the floor from both sides:

```
ruby -Itest test/preflight_test.rb
```

Green. `test_ruby_below_floor_is_fatal_and_names_floor_and_mise_command` asserts fatal on
`2.6.10`, and `test_ruby_at_or_above_floor_has_no_ruby_issue` asserts clean on `3.0.0` and
`3.3.5`. Do not modify that test file.

## Step 4: confirm no Spinel anywhere (AC2)

```
git -C /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac diff main...HEAD | grep -i spinel
```

Must print nothing.

## Step 5: confirm no auto-install branch was added (AC3)

```
git -C /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac diff main...HEAD -- scripts/install.rb bin/plastic.js | grep -nE 'mise (use|install)|mise\.run'
```

Any hit must be inside a `console.error` or a printed message string, never inside a shell-out.
If a hit is an actual command execution, that breaks AC3 and must be removed.

## Verify

The full suite:

```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac
ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
```

There is no `Rakefile` in this repo, so `rake test` does not exist. Use the loader command above.

## Done when

`README.md` states the real Ruby requirement and how to meet it on a clean Mac, no other stale
requirement claim is left in live docs, `scripts/lib/preflight.rb` has zero changed lines,
`test/preflight_test.rb` is green, and the Spinel and auto-install greps come back empty.
