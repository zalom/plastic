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
- Create intents through `scripts/new-intent` (or the `plastic-creating-intent` skill that
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

### Worktrees
- Do isolated feature work in a git worktree, not the shared checkout, so parallel sessions
  and the main working copy stay clean. Create one with the agent's worktree tool (or
  `git worktree add`), run and test inside it, then merge the branch back.
- Clean up when done: remove the worktree after the branch is merged. Never leave an orphaned
  worktree, and run `git worktree prune` if you hit a stale reference.

### Commits and releases
- Use Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`).
- Bump all version files listed in Defaults on every fix or feature release.
- Release through the `plastic-releasing` workflow (tag, GitHub release, npm publish).
- Run the full test suite (see the Testing section) and confirm green before committing code changes.
- Never push `~/.plastic/`. The global store is local-only and may contain private data.

### Release planning (Plastic project only)
Core Plastic intents carry no release numbers; the intent schema stays release-agnostic.
Which release an intent lands in is a Plastic-project decision recorded here, not in the intent
file and not in PLASTIC.md. A release is a collection of intents: a cut (tag) bundles whichever
intents have landed since the previous cut and completes them. Update this plan when an intent
is slated for a cut or when a cut ships.

Release plan:
- `1.0.0-beta.1` - shipped 2026-06-19. Promoted the alpha line; feature-complete core.
- `1.0.0-beta.2` - shipped; collected 68 (sources-vs-chain semantics). The other planned blockers (58, 49, 39, 66a) slipped to later cuts.
- `1.0.0-beta.3` - shipped; collected 74 (mandatory structured agent completion reports + deterministic fallback).
- `1.0.0-beta.4` - shipped 2026-06-21; collected 59 (Plastic owns the statusline: project-aware, colored, version+path last). Spawned 77 (guided-install statusline choice).
- Remaining beta-blockers still open for a future cut: 58, 49, 39, 66a.
- `1.0.0` (first stable) - strips the prerelease suffix and takes the `latest` dist-tag; contents beyond the beta line are TBD.
- `1.1.0` - loop engineering (intent 69 and its cluster); ships after 1.0.0 on a fresh alpha line.
