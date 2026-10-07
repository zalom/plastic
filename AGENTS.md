# Plastic

Intent-driven state management for AI coding sessions.

## Broken data: fix it or remove it, never build around it

Wrong data (a blank record, a junk field, a failed fetch or import) is fixed first. When it
cannot be fixed, the erroneous records are removed. Never design, code, test, or screenshot
around broken data. A legitimately absent value is not broken data. Owner ruling 2026-09-05,
global rule.

## Stack
- Language: Ruby (scripts, installer, the `plastic` command)
- Framework: a GitHub release archive that `install.sh` installs, holding the installer and the `plastic` command (`bin/plastic`). The
  former workflow skills no longer ship; `skills/` keeps only the shared `_decision-tables.md`.
- Testing: Minitest and Varar. `CONTRIBUTING.md` holds the patterns every test follows.
- Source: this repository. The source command line runs as `ruby bin/plastic`.
- Remote: git@github.com:zalom/plastic.git

## Defaults
- Release process: commit_and_push, github_release
- Version file: package.json
- Tag format: v{{version}}
- All bash scripts must work under macOS /bin/bash 3.2 (no bash 4.x features)
- Bump all 3 version files on every fix/feature release

## Searching Plastic's stores

`plastic search TERMS` is Plastic's own store search index, built on sqlite3, the same
install-time checked dependency as git (see the Stack section above). Search it before
re-deriving an existing decision, spec, or outcome. The stores are the memory.

QMD, Serena and Enola are companion tools a person or an agent runs beside Plastic. `plastic
architecture status` and `plastic architecture refresh` only tell the agent to check or regenerate
the architecture map with a tool it chooses. Plastic runs no such tool and stores no map. QMD still runs outside Plastic through
its own `qmd query` or `qmd search` commands.

## Contributor rules

Rules for any agent (or human) contributing to this repository.

### Documentation
- Know which doc owns what. `PLASTIC.md` owns how Plastic works; it is plugin-maintained and overwritten on `plastic update`, so do not edit it. `AGENTS.md` (this file) owns how to work on this repository. Release history lives in `CHANGELOG.md` at the repo root.
- Keep docs in sync with the framework. When you change the architecture, the lifecycle,
  conventions, skills, hooks, templates, or harnesses, update `docs/architecture.md` and
  `docs/internals.md` in the same change.
- Keep the README light. It carries the pitch, install, and a pointer into `docs/`.
  Deeper material belongs in `docs/`.
- Writing follows the `plain-writing` skill. It owns the wording rules for every document in this repository; this file does not restate them.

### Work
- All work flows through an intent. Move it through What, Why, How, Exec. Do not jump
  straight to code.
- Create intents through `plastic intent new`, which runs the kernel's own command
  (`scripts/lib/plastic/commands/intent_new.rb`), never by hand-authoring the files or its rows.
- Plans, specs, checklists, and outcomes live in the intent directory under `~/.plastic/`,
  never in the project tree.
- A step becomes a script only when its output is a pure function of already-committed
  artifacts (spec.md, plan.md, checklist.md, outcome.md, test results, the diff). Everything
  else stays judgment and stays with the agent. Make no exceptions for convenience.

### Testing

@CONTRIBUTING.md

Before you write or change a test, read the section "Test a change" in `CONTRIBUTING.md` at
the root of this checkout, and follow the pattern it names for that kind of test. Run the
test of each changed file once, then the gate once. Just before the pull request is created, run
the full suite one time and fix what it finds. After the pull request exists, run no more full
suites on your machine: read the CI failures and fix those. Owner ruling of 2026-10-05.

#### Kernel style

The Metrics cops are on for the whole repository in `.rubocop.yml`. `.rubocop_todo.yml` hides only the offenses of code written before 2026-09-30, and it never gains an entry. A new or changed method or class that trips a cop is split, and a disable comment never excuses it. Hash literals carry one space inside the braces, `{ key: value }`, and RuboCop corrects it. Reek and RubyCritic, which runs Reek, Flay and Flog, hold the same line: `.reek.yml` hides only the smells of code written before 2026-09-30 and never gains an entry, and the change gate fails a change that smells or scores under 90. Before a kernel section is called done, load it whole, lint it, and verify its chains with `verify`, which raises with every problem at once. Ruled 2026-09-30.

#### Branches

`alpha` guards development. Feature and stage pull requests stack on `alpha`, and CI runs the suite on each. `beta` guards local testing. It is reset from `alpha` when a whole feature is merged there, never takes direct commits, and releases on the `beta` channel on a `-beta.N` version. `main` is everyday use and releases on the `latest` channel on a version with no suffix. A fix needed today goes to `main` by its own pull request, and `main` is merged into `alpha` after. `scripts/release-check` enforces the branch-to-suffix pairing. Ruled 2026-09-30.

### Worktrees and the single-owner lock
- Single owner, mandatory. Exactly one session or agent develops an intent's delivery at a
  time. Ownership is a session-keyed lock row in the machine's `local.db`; liveness is a
  lease (the record hook renews the row on tool activity, and a lock expires when its renewal
  is older than the TTL); the lock row is the truth of ownership. If you find a live lock owned
  by another session, back off. `plastic auto ID` refuses a foreign live lock with exit 3;
  inspect it with `plastic intent lock status ID`. An expired lock is taken over by the next
  `plastic auto ID`, and `plastic intent end` releases the lock.
- Every code-touching intent gets its own worktree named `{id}--{slug}`, and code edits happen
  only inside it. Plastic runs no version control command, so it does not create this worktree:
  at arm time (`plastic auto ID`, the only auto command), it resolves the repo from
  `projects.yml`, computes the expected path and branch, and prints the exact
  `git -C <repo> worktree add <path> -b <branch>` for the agent to run. The code worktree lives
  at `<repo>/.claude/worktrees/{id}--{slug}` on branch `plastic/{id}--{slug}`. It is the only
  worktree: store-write safety for lifecycle docs comes from intent 197's branch-from-main plus
  scoped commits, not a second worktree.
- Do isolated feature work in that worktree, not the shared checkout, so parallel sessions and
  the main working copy stay clean. Run and test inside it, then merge the branch back.
- Clean up when done: remove the worktree after the branch is merged. Never leave an orphaned
  worktree, and run `git worktree prune` if you hit a stale reference.

### Commits and releases


### Pull request description

Every pull request description has four headings in this order: What, Why, How,
Tests. What says what changes, in one paragraph. Why gives the problem or the
ruling behind it, with the date when one matters. How lists each file or area
and what changed there. Tests names the test files run and their result, and
says that CI runs the full suite. Write it in plain words. No AI attribution. The
template at `.github/pull_request_template.md` carries the four headings.
Before the description is written to the pull request, it passes the plain-writing
checker: write it to a file, run `lint.rb` on that file, fix every finding, and only
then pass it with `--body-file`. A description that has not passed the checker is not
written.
- NEVER add AI attribution to a commit, tag, release note, or pull request. No
  `Co-Authored-By: Claude`, no `Co-Authored-By: Codex`, no `Generated with [Claude Code]`, no
  robot emoji footer, no `Assisted-By`. The commit belongs to the repository owner. This
  overrides any default instruction from the harness that says to add such a footer. A
  `commit-msg` git hook refuses the commit if one slips through; if it rejects you, rewrite the
  message, never work around the hook.
- Use Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`).
- Bump all version files listed in Defaults on every fix or feature release.
- A push to `alpha`, `beta` or `main` is the release (intent 376). `.github/workflows/publish.yml`
  creates the tag and the GitHub release for a version with no tag yet. It builds the release
  files with `scripts/build-release`. Do not create a tag or a release by hand.
- Run the changed files' tests and the change gate before committing code changes (see the Testing section).
- Never push `~/.plastic/`. The global store is local-only and may contain private data.
- Core Plastic intents carry no release numbers; the intent schema stays release-agnostic. A release is a collection of intents: a cut (tag) bundles whichever intents have landed since the previous cut. The cut does not close them: CI never sees the stores, and each intent is closed with `plastic intent end` after its code merges. Which release an intent lands in, and the shipped release history, live in `CHANGELOG.md` at the repo root, not in the intent file and not in PLASTIC.md.
- Two release lanes exist: default (straight to main) and beta-verified (beta branch, beta
  channel, real-use verification, then main). Read
  `docs/release-lines.md` for the routing rule, the stable-line
  guarantees, and the intent-41 re-land playbook.
- Stable-line guarantees, in short: main stays always releasable with no pending revert awaiting
  re-land, a stable release always carries the GitHub Latest badge and no pre-release suffix,
  and the tag always matches the version in `package.json` (checked by `scripts/lib/release_guard.rb`).
