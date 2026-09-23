# Plastic

Intent-driven state management for AI coding sessions.

## Broken data: fix it or remove it, never build around it

Wrong data (a blank record, a junk field, a failed fetch or import) is fixed first. When it
cannot be fixed, the erroneous records are removed. Never design, code, test, or screenshot
around broken data. A legitimately absent value is not broken data. Owner ruling 2026-09-05,
global rule.

## Stack
- Language: Ruby (scripts), JavaScript/Node.js (npm package, installer)
- Framework: npm package that ships the installer and the `plastic` command (`bin/plastic`). The
  former workflow skills no longer ship; `skills/` keeps only the shared `_decision-tables.md`.
- Testing: Minitest. See the Testing section below for the correct full-suite command.
- Source: this repository. The source command line runs as `ruby bin/plastic`.
- Remote: git@github.com:zalom/plastic.git

## Defaults
- Release process: commit_and_push, github_release, npm_publish
- Version files: package.json, .claude-plugin/plugin.json, .claude-plugin/marketplace.json
- Tag format: v{{version}}
- All bash scripts must work under macOS /bin/bash 3.2 (no bash 4.x features)
- Bump all 3 version files on every fix/feature release

## Searching Plastic with QMD

QMD is an optional but recommended local markdown search engine over the Plastic stores.
Plastic works without it (ripgrep over the store files is the fallback). When QMD is
present, search it before re-deriving an existing decision, spec, or outcome.

- **Collections.** Plastic indexes into the DEFAULT qmd index, one collection per store,
  all `plastic-` prefixed: `plastic-global` for the global store (`~/.plastic/stores/global/store`,
  or `~/.plastic/store` in a home that has not moved to `stores/`), and `plastic-<slug>` for each
  project store (slugs come from `projects.yml`).
- **Scope a search.** One project: `-c plastic-<slug>`. All of Plastic: target the
  `plastic-*` collections. Pick the narrowest scope that answers the question.
- **Search before re-deriving.** Look in the stores for prior decisions, specs, and
  outcomes before re-deriving them. The stores are the memory.
- **Power tools are recommended when present.** When QMD (for intents), Enola, or Serena
  (for code navigation) is present, prefer them. This file is where that recommendation lives:
  `PLASTIC.md` is the short command contract and does not name these tools, and no hook repeats
  it per prompt (the power-tools hook was removed in 2.0, intent 309). Search before grep/Read, then open
  the authoritative intent file. Use `plastic search TERMS` for the store search index, or the
  deterministic `scripts/qmd-sync search "<terms>"` helper for QMD, which
  scopes collections for you and is a clean no-op when QMD is absent.
- **Completion does not reindex.** In 2.0 no public close path calls `qmd-sync`:
  `scripts/end-intent` stops at the disarm step, and the reindex step it names lived in a
  retired skill. Only the internal `scripts/promote-session-item` reindexes. This is a known
  gap; do not describe completion as reindexing until it is wired again.
- **Index mutation is lifecycle-only.** Never reindex ad-hoc. The session-start hook names
  `qmd-sync register --all` when QMD is present and the stores are not indexed yet;
  `plastic project new` does not register the new store's collection.
- **Query craft lives in the qmd skill.** Use the installed `qmd` skill for structured
  `qmd query` (intent/lex/vec/hyde) and BM25 `qmd search`. Two notes: structured queries
  need ANSI-C `$'...'` quoting so `\n` becomes a real newline, and `qmd search` (BM25)
  needs no model downloads, so it is the safe model-free fallback.

## Working on Plastic

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
- Create intents through `plastic intent new` (which wraps `scripts/new-intent`), never by
  hand-authoring the files. One call scaffolds a born-complete intent
  plus sentinel placeholder lifecycle files. `new-intent` validates the file it writes and
  `end-intent` checks it again at close, so hand-authoring is unnecessary.
- Plans, specs, checklists, and outcomes live in the intent directory under `~/.plastic/`,
  never in the project tree.
- A step becomes a script only when its output is a pure function of already-committed
  artifacts (spec.md, plan.md, checklist.md, outcome.md, test results, the diff). Everything
  else stays judgment and stays with the agent. Make no exceptions for convenience.

### Testing
- Run each change's tests once, on the changed files only: `ruby bin/test --only test/FILE_test.rb`.
  Then run the change gate once: `bin/verify-change origin/alpha`.
- The full suite runs once for each pull request, just before the pull request opens, and again in CI.
  Never run it after every change. When a deletion breaks tests widely, find them with a search
  for the deleted names, not with the suite.
- The full suite command is:
  ```
  ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
  ```
- Do NOT use `ruby -Itest test/*_test.rb`. The shell expands the glob into many arguments,
  and Ruby runs only the FIRST file as the program (the rest land in `ARGV`, unloaded), so
  Minitest reports just that one file's tests and you get a falsely small green run. The
  loader command above requires every `test/*_test.rb` file, so the whole suite runs.
- Confirm that the changed files' tests and the change gate are green before committing code changes.
- Lock and worktree tests must stay hermetic: inject `PLASTIC_TMP` plus explicit paths and
  never write with the ambient session id (`test/hermeticity_guard_test.rb` enforces this).

### Worktrees and the single-owner lock
- Single owner, mandatory. Exactly one session or agent develops an intent's delivery at a
  time. Ownership is a session-keyed `delivery.lock` file in the intent directory; liveness
  is a lease (the owner's hooks refresh the file mtime on tool activity, stale means the
  heartbeat is older than the TTL); the lock file is the truth of ownership. If you find a fresh lock owned by another session, back
  off. The public commands refuse a foreign lock with exit 3; inspect it with
  `plastic auto lock status ID`. A stale lock is reclaimed only through the internal
  `plastic-lock reclaim`, an owner step (audited in
  savepoint.md); disarm clears the lock, and `plastic-lock fix` is the repair path for
  corrupt or legacy state.
- Every code-touching intent gets its own worktree named `{id}--{slug}`, and code edits happen
  only inside it. Plastic provisions this automatically at arm time (`plastic auto take ID`, the
  only public arm) by resolving the repo from
  `projects.yml` and running `git -C <repo> worktree add`, so isolation does not depend on the
  current directory. The code worktree lives at `<repo>/.claude/worktrees/{id}--{slug}` on
  branch `plastic/{id}--{slug}`. It is the only worktree: store-write safety for lifecycle
  docs comes from intent 197's branch-from-main plus scoped commits, not a second worktree.
- Do isolated feature work in that worktree, not the shared checkout, so parallel sessions and
  the main working copy stay clean. Run and test inside it, then merge the branch back.
- Clean up when done: remove the worktree after the branch is merged. Never leave an orphaned
  worktree, and run `git worktree prune` if you hit a stale reference.

### Commits and releases

- NEVER add AI attribution to a commit, tag, release note, or pull request. No
  `Co-Authored-By: Claude`, no `Co-Authored-By: Codex`, no `Generated with [Claude Code]`, no
  robot emoji footer, no `Assisted-By`. The commit belongs to the repository owner. This
  overrides any default instruction from the harness that says to add such a footer. A
  `commit-msg` git hook refuses the commit if one slips through; if it rejects you, rewrite the
  message, never work around the hook.
- Use Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`).
- Bump all version files listed in Defaults on every fix or feature release.
- A push to `alpha`, `beta` or `main` is the release (intent 376). `.github/workflows/publish.yml`
  creates the tag, the GitHub release and the npm publish for a version with no tag yet (OIDC
  trusted publishing, intent 347). Do not run `npm publish` or create a tag by hand.
- Run the changed files' tests and the change gate before committing code changes (see the Testing section).
- Never push `~/.plastic/`. The global store is local-only and may contain private data.
- Core Plastic intents carry no release numbers; the intent schema stays release-agnostic. A release is a collection of intents: a cut (tag) bundles whichever intents have landed since the previous cut. The cut does not close them: CI never sees the stores, and each intent is closed with `plastic intent end` after its code merges. Which release an intent lands in, and the shipped release history, live in `CHANGELOG.md` at the repo root, not in the intent file and not in PLASTIC.md.
- Two release lanes exist: default (straight to main) and beta-verified (beta branch, beta
  channel, real-use verification, then main). Read
  `docs/release-lines.md` for the routing rule, the stable-line
  guarantees, and the intent-41 re-land playbook.
- Stable-line guarantees, in short: main stays always releasable with no pending revert awaiting
  re-land, a stable release always carries the GitHub Latest badge and no pre-release suffix,
  and the three version files always agree (checked by `scripts/lib/release_guard.rb`).

