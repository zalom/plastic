# Plastic

Intent-driven state management for AI coding sessions.

## Stack
- Language: Ruby (scripts), JavaScript/Node.js (npm package, installer)
- Framework: npm package (CLI installer), flat personal skills
- Testing: Minitest. See the Testing section below for the correct full-suite command.
- Source: /Users/zlatko/apps/personal/plastic
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
  all `plastic-` prefixed: `plastic-global` for `~/.plastic/store`, and `plastic-<slug>`
  for each project store (slugs come from `projects.yml`).
- **Scope a search.** One project: `-c plastic-<slug>`. All of Plastic: target the
  `plastic-*` collections. Pick the narrowest scope that answers the question.
- **Search before re-deriving.** Look in the stores for prior decisions, specs, and
  outcomes before re-deriving them. The stores are the memory.
- **Power tools are recommended when present.** When QMD (for intents), Enola, or Serena
  (for code navigation) is present, prefer them: the UserPromptSubmit hook appends one
  recommendation line per present tool, Enola-first when both code-navigation tools are
  present (one code-navigation slot, Enola wins over Serena), and the per-skill
  QMD-first steps run `qmd-sync search` before grep/Read, then open the authoritative
  intent file. Use the deterministic `scripts/qmd-sync search "<terms>"` helper, which
  scopes collections for you and is a clean no-op when QMD is absent.
- **Completion fires an async reindex.** Intent delivery reindexes the delivering store's
  collection in the background (non-blocking), so the index stays fresh while
  "index mutation is lifecycle-only" stays true. Never reindex ad-hoc.
- **Index mutation is lifecycle-only.** The index changes only on Plastic lifecycle events
  (install registers all stores, project creation registers the new project store, intent
  delivery reindexes the delivering store's collection). Never reindex ad-hoc.
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
- User-facing documents (README, `docs/`, AGENTS.md, CLAUDE.md) avoid AI tell-tale signs.
  Do not use em-dashes. Use commas, periods, parentheses, or colons. Internal store and
  intent files are exempt from this rule.

### Work
- All work flows through an intent. Move it through What, Why, How, Exec. Do not jump
  straight to code.
- Create intents through `scripts/new-intent` (or the `plastic-intent-creating` skill that
  wraps it), never by hand-authoring the files. One call scaffolds a born-complete intent
  plus sentinel placeholder lifecycle files. The write-time create gate blocks an incomplete
  or malformed intent file, so hand-authoring is both rejected and unnecessary.
- Plans, specs, checklists, and outcomes live in the intent directory under `~/.plastic/`,
  never in the project tree.

### Testing
- Run the full suite with:
  ```
  ruby -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
  ```
- Do NOT use `ruby -Itest test/*_test.rb`. The shell expands the glob into many arguments,
  and Ruby runs only the FIRST file as the program (the rest land in `ARGV`, unloaded), so
  Minitest reports just that one file's tests and you get a falsely small green run. The
  loader command above requires every `test/*_test.rb` file, so the whole suite runs.
- Confirm green before committing code changes.
- Lock and bridge tests must stay hermetic: inject `PLASTIC_TMP` plus explicit paths and
  never write with the ambient session id (`test/hermeticity_guard_test.rb` enforces this).

### Worktrees and the single-owner lock
- Single owner, mandatory. Exactly one session or agent develops an intent's delivery at a
  time. Ownership is a session-keyed `delivery.lock` file in the intent directory; liveness
  is a lease (the owner's hooks refresh the file mtime on tool activity, stale means the
  heartbeat is older than the TTL). The /tmp session bridge is only a cache: on any
  disagreement the lock file wins. If you find a fresh lock owned by another session, back
  off. A stale lock is reclaimed only through `plastic-lock reclaim` (audited in
  savepoint.md); disarm clears the lock, and `plastic-lock fix` is the repair path for
  corrupt or legacy state.
- Every code-touching intent gets its own worktree named `{id}--{slug}`, and code edits happen
  only inside it. Plastic provisions this automatically at arm time by resolving the repo from
  `projects.yml` and running `git -C <repo> worktree add`, so isolation does not depend on the
  current directory. The code worktree lives at `<repo>/.claude/worktrees/{id}--{slug}`; the
  paired store worktree lives at `<plastic_home>/.worktrees/{id}--{slug}`.
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
- Release through the `plastic-releasing` workflow (tag, GitHub release, npm publish).
- Run the full test suite (see the Testing section) and confirm green before committing code changes.
- Never push `~/.plastic/`. The global store is local-only and may contain private data.
- Core Plastic intents carry no release numbers; the intent schema stays release-agnostic. A release is a collection of intents: a cut (tag) bundles whichever intents have landed since the previous cut and completes them. Which release an intent lands in, and the shipped release history, live in `CHANGELOG.md` at the repo root, not in the intent file and not in PLASTIC.md.
- Two release lanes exist: default (straight to main) and beta-verified (beta branch, beta
  channel, real-use verification, then main). Read
  `skills/releasing/references/release-lines.md` for the routing rule, the stable-line
  guarantees, and the intent-41 re-land playbook.
- Stable-line guarantees, in short: main stays always releasable with no pending revert awaiting
  re-land, a stable release always carries the GitHub Latest badge and no pre-release suffix,
  and the three version files always agree (checked by `scripts/lib/release_guard.rb`).
