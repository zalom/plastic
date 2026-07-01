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
- **Power tools are mandated when present.** When QMD (for intents) or Serena (for code
  navigation) is present, using them is mandatory, not just recommended: the
  UserPromptSubmit hook appends a MUST-use obligation per present tool, and the per-skill
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

### Worktrees and the single-owner lock
- Single owner, mandatory. Exactly one session or agent develops an intent's delivery at a
  time. Ownership is the armed session bridge, which acts as the delivery lock (it records the
  owning session, the owner pid, the acquired-at time, and the host). If you find an armed
  bridge for an intent whose owner pid is still live, back off; you may reclaim it only when
  the owner is dead.
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
- `1.0.0-beta.5` - shipped 2026-06-21; collected the QMD/Serena power-tools mandate cluster: 66b (mandated QMD+Serena harness, detect-then-degrade), 66c (async reindex on completion), 66a (QMD-first search step across 9 store-searching skills + qmd-sync search verb).
- `1.0.0-beta.6` - shipped 2026-06-22; collected 78 (fix the installer manifest gap from 66b: power_tools.rb was never added to InstallerCore#core_files, so it never installed into ~/.plastic and the UserPromptSubmit qmd hook raised a LoadError on every prompt; adds the manifest entry plus a regression-guard test asserting every scripts/lib/*.rb is in the manifest).
- `1.0.0-beta.7` - shipped 2026-06-22; collected 66c1 (extends 66c: the plastic-intent-curator async QMD reindex now fires on any terminal-state transition - move to Completed OR Abandoned - not completion only; prose-wiring, no new Ruby).
- `1.0.0-beta.8` - shipped 2026-06-22; collected 79 (per-session statusline via the session Bridge: the statusline resolves the work-unit from the current session's live bridge instead of the shared newest-savepoint heuristic, so parallel sessions stop overwriting each other's line; added a CLAUDE_CODE_SESSION_ID fallback to Bridge.resolve_session). Spawned 80 (bridge cleanup on work-done) and 81 (savepoint state from the ledger).
- `1.0.0-beta.9` - shipped 2026-06-22; collected 49 and 72 (store-wide knowledge-graph consistency). 49: deterministic rebuild-graph tool plus a graph_cross_store_resolution doctor check (one-directional I1/I3/I4, preserve I2, cross-store relocation resolution that fixed the global:24 id-reuse hazard). 72: fence-aware project-links tool plus a graph_links_projection doctor check; canonical ## Links projection store-wide (id--slug target, full intent label, sources-first mandatory ordering); the I5 rule codified in PLASTIC.md, the concept doc, and the references; new-intent now emits canonical Links at creation so drift is prevented at the source. Spawned 82 (improve Insights: exact timestamps plus tightened background-agent delivery).
- `1.0.0-beta.10` - shipped 2026-06-22; collected 80 (bridge cleanup on work-done). Replaced intent 67's 48h age-window purge with terminal-state cleanup in core bridge.rb: purge_done_bridges removes a /tmp/plastic-*.json bridge only when its intent is no longer Active in its store's INDEX (keyed by intent.id plus intent.store via new intent_active?); active intents' and the current session's bridges are never purged (continuation signal plus anti-collision lock); removed PURGE_AGE_SECONDS; arm/disarm repointed. Bridge and savepoint are independent mechanisms (not dependent on 81). One-time live clean slate took /tmp from 451 to 1. Folds in 73 follow-up #2; 73 follow-up #1 is owned by sibling 73b.
- `1.0.0-beta.11` - shipped 2026-06-22; collected 73b (fix skill session-id resolution prose: plastic-auto arm/disarm examples pass CLAUDE_CODE_SESSION_ID, not the always-empty CLAUDE_SESSION_ID; headless notes corrected). Owns 73 follow-up #1.
- `1.0.0-beta.12` - shipped 2026-06-23; collected the 73c worktree-isolation chain (73c decision + 73c1/73c2/73c3). Plastic-supplied per-intent isolation: new scripts/lib/worktree.rb provisions a mandatory code worktree plus a consistency store worktree at arm time via `git -C <repo-from-projects.yml>` (cwd-independent, closing the one genuine harness GAP from 73 matrix); the session bridge becomes a single-owner delivery lock (owner_session/pid/acquired_at/host) with stale-lock reclaim via pid liveness; Bridge.worktree_gate_decision hard-blocks code edits outside the intent worktree and non-owner edits to live-locked active intents, composed into hook-code-gate with a logged fail-open matrix; Worktree.finish merges-then-removes on the release path and ensure_gitignored keeps .worktrees/ and .claude/worktrees/ out of the git index; single-owner plus mandatory-worktree doctrine added to PLASTIC.md and AGENTS.md. Suite 606/0/0. Spawned 73c1a (isolate bridge writes in tests).
- `1.0.0-beta.18` - shipped 2026-06-25; collected 89a (operation-based retrieval gate: only CONTENT SEARCH over a store is hard-gated to QMD; reads and structural ops like Read/cat/find/ls/Glob are always allowed, including over the store; the Serena hard-gate is removed and code navigation stays a soft UserPromptSubmit mandate with content grep over code allowed; a tier-b warn fires when QMD is present but its freshness probe breaks; block reason teaches the semantic not score-based # qmd-ok fallback. Suite 712/0. Spec in intent 89a, policy map in intent 89, from grill-me brainstorm).
- `1.0.0-beta.19` - shipped 2026-06-25; collected 92 (plastic-humanizer skill: clean authored prose, remove AI tells and slop from docs/specs/outcomes/READMEs).
- `1.0.0-beta.20` - shipped 2026-06-29; collected 98 (scrub the phantom CLAUDE_SESSION_ID from the whole repo: resolve_session drops its dead env fallback so the chain is explicit-stdin then CLAUDE_CODE_SESSION_ID then derived key; the five hooks that read the phantom as a live fallback swap to CLAUDE_CODE_SESSION_ID, preserving the background/headless real-id path; comment, doc, agent, and skill prose reworded to stop naming the phantom while keeping the rationale; six test files rewired to inject via CLAUDE_CODE_SESSION_ID with ambient-clear. Suite 711/0). Also carried 85 already-landed creating-skills code (b74bf43), completed but not yet cut.
- `1.0.0-beta.21` - shipped 2026-06-29; collected 85c (creating-skills global-hook improvements: token-reduction and propose-only self-improving pointers in references/hooks.md E7/E8, output-token axis noted as guidance-only, eval depth with real assertions plus a hermetic scaffolder test; A-G standard rule E7). Spawned future intents 100 (verifying-skills), 101 (improving-skills), 102 (portable-hooks-via-adapters), 103 (scoped-hooks-ecosystem-research), 104 (token-trimmer-hook); related 76. Suite 716/0/0.
- `1.0.0-beta.22` - shipped 2026-06-30; collected 96 (hard-block work on an intent without a lock: arm_guided lock acquisition, a fail-closed L1 PreToolUse lock-gate that JSON-denies a no-lock mutating write to an active intent own dir with per-intent scope and pid/host staleness, and the /plastic-intent-starting Start procedure: lock first, confirm savepoint, ask auto/guided once, board at the latest delivered station). Suite 745/0/0.
- `1.0.0-beta.23` - shipped 2026-07-01; collected 107 (revisions.md structural-maintenance audit trail: an optional append-only per-intent audit file where the intent-curator relocates a misplaced section, file, or ref via a dated, rule-tagged, move-and-record entry without altering delivered meaning; template plus PLASTIC.md contract plus docs plus curator role plus two guard tests, no runtime logic since revisions.md is invisible to every validator/gate/doctor). Spawned future intents 108 (test and fix the locking mechanisms; two defects found during delivery) and 109 (audit README against the shipped PLASTIC implementation). Suite 747/0/0.
- Remaining beta-blockers still open for a future cut: none. (49 shipped in beta.9; 39 abandoned 2026-06-22, superseded by 36a/52; 58 abandoned 2026-06-22, out of scope, rationale folded into 73.)
- `1.0.0` (first stable) - strips the prerelease suffix and takes the `latest` dist-tag; contents beyond the beta line are TBD.
- `1.1.0` - loop engineering (intent 69 and its cluster); ships after 1.0.0 on a fresh alpha line.
