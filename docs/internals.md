# Plastic Internals

This is the deeper companion to the README's "How Plastic Works" section. The
README states the idea; this document explains the operational mechanics: how
Plastic makes work come out the same shape no matter who or what produces it,
how tight that guarantee actually is today, and what is still missing.

## deterministic-by-design

Plastic splits every unit of work into two parts.

- **The blueprint** is the deterministic part: conventions, templates, directory
  structure, lifecycle stages, gates, IDs, and linking rules. It describes *how
  to fill in the work*.
- **The brain** is the non-deterministic part: the human or LLM that does the
  actual thinking. Plastic never replaces it. It only steers the brain's input
  and validates the brain's output.

The line between them is precise: determinism lives in the **form** of artifacts
(their sections, ordering, frontmatter schema, file naming, IDs, and placement),
never in the brain's reasoning. Two brains given the same desire and the same
store state must produce artifacts of identical form even though the prose inside
the sections differs. That is the whole contract: form is fixed, wording is free.

The test for whether a rule belongs to the blueprint is the **run-it-on-paper
test**. If a person with no tooling and no AI, working in a plain text editor,
can apply the rule by hand and reach the same answer every time, the determinism
is genuinely in the form. The ID algorithm passes (read the existing IDs, apply
the alternating Folgezettel rule, get one answer). A skill's prose instruction to
"write a good spec" does not pass: two brains will produce two different shapes.
Everything Plastic constrains is built to pass the paper test.

## the-determinism-breakdown

An audit classified all **93** user-facing surfaces of Plastic against this
model. Each surface is one of three classes:

- **deterministic-now**: produces identical form regardless of which brain runs
  it (script output, a frontmatter schema, directory naming, a blocking gate
  hook, a hardcoded instruction string).
- **mixed**: a deterministic skeleton with brain-loose pockets (a template fixes
  most sections, but some section content or format is left to brain judgement).
- **brain-loose**: defined only by skill prose that an LLM interprets, so layout,
  format, and structure can drift between two different brains.

| Classification | Count |
|----------------|-------|
| deterministic-now | 70 |
| mixed | 18 |
| brain-loose | 5 |
| **Total** | **93** |

About **75%** of Plastic (70 of 93 surfaces) is already deterministic by
construction.

**What makes the 75% deterministic.** The entire executable layer: every script,
hook, and test, plus the gate hooks that block on filesystem preconditions, the
frontmatter and directory schema, the fixed templates, and the script-output
skills that show a renderer's output verbatim (dashboard, continuing, uninstall,
versions). Where Plastic ships *code*, the form is owned by code and cannot
drift. The dashboard is a near-miss on this line: the script owns the data
(`dashboard.rb --data` emits a complete, deterministic JSON payload), and the
skill does only a mechanical fill of a fixed Markdown template before presenting
it, so the model never sorts, classifies, or summarizes. Determinism lives in
the payload, which is golden tested alongside the text and JSON snapshots.

**Where looseness concentrates.** In the prose skills that produce *written
deliverables*. Determinism is weakest exactly where Plastic ships prose that asks
a brain to author an artifact. The brain-loose 5 are the design and judgement
skills (`brainstorming`, `brainstorming-grill-me`) and the curator surfaces
(`intent-curator` as both skill and agent, plus `future-intent-researcher`).
These produce `spec.md` and INDEX or cluster reorganizations with no output
template at all: section set, ordering, depth, cluster naming, and orphan
thresholds all drift. **`spec.md` is the single least-constrained artifact in the
framework**, because historically no template existed for it.

Auto mode adds five more agent surfaces, the role files that ship in `agents/`:
`plastic-brainstorming`, `plastic-spec-specialist`, `plastic-planner`,
`plastic-executor`, and `plastic-enforcer`. They are thin handoff contracts (one
role per cycle stage) rather than free-prose producers: each names what it consumes
and produces, and the enforcer (which is the auto orchestrator itself) sequences and
gates them. The installer syncs `agents/` into each harness agent directory and
tracks the role files in the manifest, so they prune on update and uninstall with the
skills and hooks. The team model lives in `skills/auto/references/agent-architecture.md`.

The mixed 18 are template- or script-backed skills with free-prose content
pockets: the lifecycle producers, the execution skills, the maintenance skills,
the `intent.md` template (fixed skeleton, free prose sections), and the two
recorded `evals.json` files (fixed schema, brain-written assertions).

## the-harness-system

A **harness** is anything that constrains a brain step toward blueprint-conforming
form. Harnesses come in two layers, distinguished by *who needs them*.

**Layer 1: shared harnesses (human and AI).** These ARE the blueprint. A human
learns them and walks the cycles in order; they constrain everyone identically.
Three mechanisms:

- **Convention**: the rules a brain must obey (the ID algorithm, slug shape, gate
  order, state-from-files derivation, INDEX placement and cluster threshold, link
  rules). A fixed written rule whose output is determined by its input.
- **Template**: the form of a produced artifact (its frontmatter schema, required
  sections, exact order, file name). A literal skeleton the brain fills, with
  empty sections written `None` so the section set is identical for everyone.
- **Directory structure**: the placement of artifacts (the `ID--slug/` folder,
  reserved lifecycle file names, everything else under `resources/`).

**Layer 2: agent-extra harnesses.** An AI agent lacks a human's innate senses: it
does not feel fatigue, does not sense when working memory is full, does not carry
the lifecycle order in its body. Where a human supplies a behaviour from instinct,
an agent needs explicit scaffolding to reproduce it. Each agent-extra harness is
defined by reference to the human behaviour it mirrors. Two mechanisms:

- **Eval**: constrains an agent's skills (the procedures it runs). A recorded
  check that running a skill on a known input yields a conforming artifact. It
  mirrors the human behaviour of *inspecting your own finished work against the
  standard before calling it done*.
- **Hook + instruction**: constrains an agent's reasoning at runtime. A trigger
  that fires on a runtime event and injects a steering instruction (or blocks
  until a precondition holds). It mirrors the human behaviours of *knowing the
  lifecycle order*, *feeling when to save state*, and *leaving yourself a note
  when too tired to continue* (so: stop and save state, leave a note when context
  runs out, do not plan before specifying).

**The three constrainable points.** A brain step has exactly three points where
form can be constrained, and the mechanisms partition them:

1. **input-steer**: the input, before or while the step runs. That is
   hook + instruction (inject a rule, or block on an unmet precondition).
2. **form-fix**: the artifact shape the step must hit. That is template, backed
   by convention and directory-structure for rules and placement.
3. **output-verify**: the output, after the step runs. That is eval.

Input-steer, form-fix, and output-verify are the full surface of a brain step.
There is no fourth point at which a step can be harnessed, so the
three-mechanism agent-extra set (eval, hook + instruction, template) is
**complete**. New triggers extend existing mechanisms rather than adding new ones
(the context-full savepoint is the felt-savepoint behaviour bound to a second
trigger, not a new mechanism).

The cycle-step savepoint ledger (intent 34) is a clear instance of this. `savepoint.md`
is no longer a hand-written prose note; it is a deterministic, append-only, one-line-per-
milestone ledger (newest at the bottom) that the `gate-check` hook writes automatically at
each lifecycle boundary. That is the existing hook mechanism bound to the artifact-write
trigger, with the ledger as a derived form-fix on top. It is sugar over the conventions,
never a source of truth: state stays derivable from files-on-disk and the ledger is
rebuildable via `Bridge.rebuild_savepoint`. The `plastic-savepoint` skill is now a thin
reader/verifier, not a writer.

Session resolution feeds the bridge that the gate hooks read (intent 52). Claude Code does
not export `CLAUDE_SESSION_ID` into the hook environment; it passes `session_id` on the hook
stdin JSON. So the bash wrappers parse `session_id` out of stdin (in Ruby, never in bash) and
hand it to the gate scripts as a second argument. `Bridge.resolve_session` then takes the
first non-empty of three sources, in precedence order: the explicit stdin `session_id`, the
`CLAUDE_SESSION_ID` environment variable, and a derived `auto-<digest>` key
(`Bridge.derive_key`, a short SHA256 of `store/intent_id`). The derived key is deterministic,
so a session-less arm and a later session-less gate-check resolve to the same bridge file
instead of writing `plastic-.json` with a null session. `Bridge.write` now refuses an empty
session, so a null-session bridge can never be persisted.

The savepoint write is decoupled from bridge resolution (intent 52). `hook-gate-check` derives
the intent directory straight from the written file path via `Bridge.intent_dir_for` (it walks
up to the first ancestor matching `.../store/<id>--<slug>`) and appends the savepoint there
BEFORE any bridge lookup. A missing bridge, an unset session, or a headless background run can
no longer skip the ledger. Bridge discovery itself is also tighter: `Bridge.discover_bridge`
prefers an exact-session match, then scans `/tmp/plastic-*.json` keeping only valid bridges,
preferring auto-armed ones, then those whose `intent.store` matches the current working
directory, breaking ties by newest mtime. The `/tmp` directory is injectable so the scan is
testable against a fake directory.

Because that scan parses every `plastic-*.json` on each fire, the temp directory has to stay
small or the per-fire cost grows without bound (intent 67). `Bridge.purge_done_bridges` runs
on `arm_auto` and on `disarm_auto`, so every auto run cleans up dead bridges at its start and
at delivery. The rule is terminal-state, not age-based (intent 80). A bridge is purged only when
its intent is terminal: its id is no longer in its store's `INDEX.md` `## Active` block.
`Bridge.intent_active?` resolves that INDEX from the bridge's own `intent.store` (the INDEX lives
at the parent of the `store/` directory), scans only the `## Active` section, and reports whether
the bridge's `intent.id` is listed. An Active intent's bridge is kept unconditionally, because
while the intent is live the bridge is load-bearing: it is the continuation signal (a parked or
interrupted run resumes from it) and the anti-collision lock that keys the per-session statusline.
The current session's own bridge is never purged (preserving the `disarm_auto` contract that it
stays readable), and a bridge that cannot be parsed or that carries no `intent.id` or
`intent.store` is treated as junk and removed. An age window was the wrong axis: it left dead
bridges resident for up to two days and could reap bridges of interrupted-but-still-active
intents, which are exactly the ones to preserve. The sweep is best-effort and never raises (a
file that another job already deleted, or any other error, is swallowed), so it can never break
arming or delivery. `intent_active?` accepts an injectable `index_active_ids:` array and the temp
directory is injectable, so the rule is testable hermetically.

The `plastic-continuing` skill consumes that ledger on the resume path (intent 36): when the
user or an agent asks to continue a specific intent, the skill reads the last ledger line as
the current stage, confirms the named stage file is present and non-empty, calls
`Bridge.rebuild_savepoint` when the ledger and the filesystem disagree, and derives the next
step from the first unchecked checklist item. Continue runs this only on demand, not on every
boot, since continue is about loading and presenting choices while `plastic-auto` owns
autonomous execution.

`doctor.rb` has three scopes:

- **`--core`**: binary pass/error only. Walks agent registration and core files
  (hooks, skills, scripts, PLASTIC.md, VERSION, version match) and compares each
  file's content against its SHA256 in the install manifests. The global manifest
  (`~/.plastic/manifest.json`) covers PLASTIC.md and global scripts; the agent-side
  manifest (`~/.claude/plastic/manifest.json`) covers agent scripts, hooks, skills,
  and the installed `agents/` role files, so `--core` SHA-verifies the role files too.
  Agent registration also runs an `agents_exist` check that passes when at least one
  `plastic-*.md` role file is present in the harness agent directory. The
  installer writes both manifests on every install or update. `--core` skips all
  store inventory walks so it returns in well under a second. Result is binary: exit 0
  on pass, non-zero on error, never a warning.

- **`--store [global|<slug>]`**: three-state (pass / warn / fail). Walks store state:
  intent well-formedness, INDEX sections, conventions, and link validity. Without an
  argument it checks all stores; `global` checks only the global store; a project slug
  checks only that project's store. The dashboard load triggers this automatically: the
  global board runs `--store global`, a project board runs `--store <slug>`. The
  `plastic-continuing` skill also calls it on resume.

- **Full run (no flag)**: three-state. Walks every check category (global store,
  conventions across all intents, agent registration, core files, project stores,
  deprecations). This is what `/plastic-doctor` invokes. It also runs automatically
  after every `plastic-update` (informational: prints the report but does not block
  or revert the update).

The project-stores category includes an additive `project_store_dir` check
(intent 61): when a registered project's `store/` directory is missing, it warns
and is fixable, with the fix `provision-project-store {slug}`. Doctor stays
read-only; the doctor skill applies the fix by running the verb.

`hook-session-start` calls `--core` in-process (reusing the `Doctor` class, no second
process spawn) to drive the boot banner on every session start (intent 36a).

The hook surfaces that banner on two channels from a single `BootBanner` renderer (intent 54):
`hookSpecificOutput.additionalContext` (added to the model's context) and the top-level
`systemMessage` (rendered in the user's terminal, and re-fired on `/clear`). The banner is
binary: success produces one line, error produces one line with a prompt to run
`/plastic-doctor`. Sharing one renderer means the visible line and the model-facing line
cannot drift.

## what-exists-today-vs-what-is-missing

Plastic ships **23** harness entries today. By strength on the form-determinism
axis (hard-block beats soft-steer beats advisory):

| Strength | Count | Examples |
|----------|-------|----------|
| hard-block | 7 | the lifecycle gate, the code gate, the ID and hash scripts, the dashboard renderer, config resolution |
| soft-steer | 10 | the prompt hooks, the savepoint hook, the intent/checklist/plan/savepoint/index templates |
| advisory | 6 | session-start and statusline hooks, the PLASTIC.md and active-intent-gate conventions, both `evals.json` files |

Two honest caveats about the existing harnesses:

- **The lifecycle gate runs after the write lands.** The strongest stage-gate
  mechanism in the framework, `gate-check`, is wired as a PostToolUse hook: it
  rejects the write *after* the file already exists on disk, so a brain that
  ignores the block leaves a half-written artifact behind. It checks lifecycle file
  *presence* (sentinel-aware since intent 60b), not the section form of those
  files. For the intent file specifically, the intent-60b create gate
  (`hook-create-gate`) closes this gap on the create path: it is a PreToolUse hook
  that blocks *before* the write and validates frontmatter plus the sanctioned `##`
  section set (see the sanctioned-creation-path section below).
- **The eval suites do not run.** Both `evals.json` files are advisory records.
  One carries triggering and one sequencing case; the other has empty assertion
  arrays (`assertions: []`) on every case. There is no runner that asserts
  artifact form, so nothing mechanically verifies the produced shape.

Derived from the harness taxonomy's guarantees minus what any existing harness
backs, there are **13** net-new harnesses. The top 5 by priority (determinism
impact times how often the step runs):

1. **spec.md template + eval**: the loosest artifact, runs every intent. Ship
   `templates/spec.md` (nine sections, `None` placeholders) and a form eval.
2. **outcome.md template + eval**: free prose in every execution path, runs
   every completed intent. Ship `templates/outcome.md` and a form eval.
3. **lifecycle-gate realignment**: fix the gate preconditions to match the
   blueprint, add a section-form pre-check, and evaluate moving it to PreToolUse.
4. **runnable form-assertion eval harness**: build the eval runner and a
   reusable form-assertion library; it unblocks every other eval.
5. **INDEX placement + cluster/orphan script**: a deterministic 3+-cluster and
   orphan-detection script plus a placement eval, tightening both curators.

These split along a **Plastic-core vs agent-implementation** line. Plastic-core
work is agent-blind and built now: the spec.md, outcome.md, research-report, and
curator-output templates, the orphan/cluster-threshold script, and the corrected
gate-precondition rule spec. Agent-implementation work (every eval, every runtime
hook, and the eval runner) depends on a specific agent's runtime and is deferred
to intent 33a.

### qmd registration and reindex flow

The optional qmd search integration mutates its index only on Plastic lifecycle
events, and one helper (`scripts/lib/qmd_sync.rb`, exposed as `scripts/qmd-sync`
with verbs `detect`, `register`, `reindex` (with an `--async` variant), `status`,
and a read-only `search`) does all the work by delegating to the qmd CLI. Each
trigger lives at a fixed point:

- **install**: the install skill registers every store as a `plastic-`
  prefixed collection (`register --all`).
- **project creation**: the creating-project skill registers the new project
  store's collection (`register --store <dir>`).
- **intent delivery**: the delivery/completion path reindexes the delivering
  store's collection. This is mandatory on completion and runs async
  (`reindex --store <dir> --async`) so it never blocks the turn. The sync
  `reindex` runs `qmd update` then `qmd embed -c plastic-<slug>` inline;
  `QmdSync.reindex_async` runs the same work detached via `Process.spawn` plus
  `Process.detach`, with output discarded, returning immediately. Both no-op when
  qmd is absent.
- **search**: the read-only `search "<terms>" [--store <dir>]` verb wraps
  `QmdSync.search`, scoping collections by `--store` (that store's collection plus
  `plastic-global`) or by CWD (`collections_for_cwd`), and prints ranked hits as
  `[<pct>%] <path> - <title>`. The per-skill QMD-first steps call it before
  grep/Read; it no-ops cleanly (exit 0) when qmd is absent.
- **session start**: report-only. The boot path may report index status but
  never mutates it.
- **doctor**: a qmd check verifies the integration is healthy, including that the
  ~2GB of models qmd lazily downloads on first embed/rerank are present. The index
  itself lives under `~/.cache` and is never committed to the `~/.plastic` git.

The search side (read-only, never mutates the index) is exercised on every turn by
the power-tools `UserPromptSubmit` hook (`hooks/qmd-search` ->
`scripts/hook-qmd-search`, decision logic in `scripts/lib/qmd_hook.rb`,
search in `QmdSync.search`). Gated on a substantive prompt (the `< 10` char and
bare-`continue` guards mirror `future-intent-check`), its output is composed of two
parts. When qmd is on PATH it runs `qmd search --json` (BM25, no model downloads)
over the CWD's project collection plus `plastic-global` and injects only hits above
`min_score` (default 0.5, capped at 3) framed as related or prior intents. It then
appends the power-tools mandate from `scripts/lib/power_tools.rb`
(`PowerTools.mandate`): an always-on "MUST use QMD" obligation when qmd is present
and a "MUST use Serena" obligation when Serena is present (symbolic code navigation
before grep/Read). Serena presence is detected by a `.serena` marker in the working
directory or an ancestor, or `serena` on PATH (`PowerTools.serena?`); qmd presence
by `PowerTools.qmd?`. These are mandates, not soft reminders. A 2s timeout plus
rescue-all keeps a slow or broken qmd from ever blocking the turn; when neither tool
is present the hook is a silent no-op. The hook registers as a fourth
`UserPromptSubmit` entry in `merge_claude_hooks`, ships via `core_files`, and is
listed in doctor's `CLAUDE_HOOK_SCRIPTS`.

### intent born-complete validation

An intent can be born missing a required frontmatter field (intent 51 was created
with no `chain` key, and nothing caught it until a later doctor run). The fix is
one shared definition of "born complete" that creation and diagnosis both consult.

- **Single source of truth**: `scripts/lib/intent_validator.rb` is the only
  definition of born-complete (required fields present, `sources` and `chain`
  well-formed arrays of id references (bare ids, or cross-store references like global:1a2)). It is injectable (`plastic_home`), hermetic,
  uses no eval, and does no global-constant injection, mirroring `qmd_sync.rb`.
- **Three consumers sit on top of it**: the `validate-intent` CLI (exit 0 when
  complete, non-zero with a report otherwise); the `plastic-creating-intent`
  self-verify step (run the CLI on the just-written file, inject any missing field
  such as `chain: []`, then re-run before announcing or committing); and doctor's
  read-only conventions checks. Doctor's `frontmatter_fields` check is now
  repairable through its `fix_hint` (the intent-19a pattern: doctor never writes,
  the doctor skill applies the fix), and a new `frontmatter_valid` check flags
  malformed `sources` or `chain`. There is no `--fix` flag on `doctor.rb`.
- **Section structure (intent 60b)**: the validator also carries
  `SANCTIONED_SECTIONS` plus a pure `validate_sections`, folded into `validate`, so
  born-complete now means frontmatter complete AND the sanctioned `##` section set
  present with no unknown sections. The same three consumers (CLI, gate, doctor)
  plus the create gate share this one definition. See the sanctioned-creation-path
  section below.
- **Scope boundary**: this is per-intent frontmatter and section validity only.
  Store-wide `sources`/`chain` symmetry across intents is owned by intent 49 (below).

### store-wide graph rebuild (intent 49)

Per-intent validation cannot see asymmetry between intents, so the cross-intent
`sources`/`chain` graph is maintained by a separate, pure-logic-plus-IO pair:

- **`scripts/lib/graph_rebuild.rb`** (pure `GraphRebuild`): a relocation-map builder
  + cross-store resolver, and the per-store rebuild transform. `build_relocation_map`
  parses every store's `## Relocated` log (both the `global:24 → project:22c` form
  and the backtick bare-id `1b1a1 → 41` form), collapses multi-hop chains to their
  final hop, and is cycle-guarded. `resolve_ref` consults that map BEFORE direct id
  resolution, so a recorded relocation always wins over a coincidentally-reused id.
  This is the **named id-reuse hazard**: `plastic:11.sources` carried `global:24`,
  whose target was relocated to `22c`, but a brand-new unrelated `global:24`
  (visual-ui-layer) was later created. Direct resolution would silently accept the
  impostor; relocation-first repoints it to bare `22c`. `rebuild_store` applies the
  load-bearing order dedupe -> I3 (formative edge wins, dropped from chain) ->
  cross-store resolve (repoint / collapse-to-bare-same-store / drop-dead) -> I1
  in-store backlinks, while I2 relational forward links are never stripped and no
  reciprocal source is ever synthesized. It is a deterministic fixpoint: a second
  pass yields zero changes.
- **`scripts/lib/frontmatter_writer.rb`** (pure `FrontmatterWriter`): a minimal,
  style-preserving rewrite of just the `sources:`/`chain:` arrays in a content
  string. It detects flow (`["40"]`) vs block (`- '1a'`) style per array and
  preserves it, leaves every other key and the whole body byte-identical, never
  touches `## Links` (that projection is intent 72), and is a no-op when the arrays
  are unchanged.
- **`scripts/rebuild-graph`** (executable IO shell, DI `--plastic-home`/`--dry-run`/
  `--audit-path`): loads the three stores, builds the maps, runs the transform per
  store, emits a per-store before/after audit grouped by kind (dedupes, I3
  resolutions, I1 backlinks, cross-store repoints/collapses, drops), then writes the
  changed frontmatter back. Pure Ruby (no bash). Never runs git; `~/.plastic` is
  committed by hand and never pushed.
- **Doctor's `graph_cross_store_resolution` check**: the i1/i3/i4 checks
  (`graph_invariant_checks`) deliberately treat a `store:id` ref as out-of-scope and
  validate only its shape, so a well-formed ref at a relocated or deleted target was
  invisible. The new check RESOLVES every cross-store ref against the full store
  family (relocation-first) even under `--store` scoping (only the REPORTED findings
  are filtered to the scoped origin), flagging dead and relocated-stale refs
  alongside i1/i3/i4. Its fix hint points at `scripts/rebuild-graph`.

## sanctioned creation path (intent 60b)

Intent 60 enforced the born-complete OUTCOME but not the PROCESS: an agent could
bypass `plastic-creating-intent` and hand-author intent files with the same Write
primitive the skill uses. Process-purity is unprovable (the skill and a
hand-author look identical at the tool layer), so the achievable targets are the
INVARIANT (every intent file is born complete and structurally sanctioned) plus
the ERGONOMICS (the sanctioned path is the cheapest action an agent can take).
Four coordinated pieces deliver that.

- **Placeholder sentinel plus one shared predicate.** A scaffolded lifecycle file
  (`spec.md`/`plan.md`/`checklist.md`/`outcome.md`) carries the exact first line
  `<!-- plastic:placeholder -->` until an agent fills it and deletes the sentinel.
  `Bridge.stage_file_present?(path)` is the single present-and-real predicate: it
  returns false when the file is missing OR its head carries the sentinel, and it
  reads only the file head (never the whole file) so the dashboard stays fast
  across many intents. It replaced every bare lifecycle-file `File.exist?` in stage
  detection (`derive_stage`, `has_files`), the gates (`check_gate`,
  `code_gate_decision`), and the savepoint trio (`append_savepoint`,
  `rebuild_savepoint`), plus `dashboard.rb` (`parse_intent` flags and the
  completed-on-`outcome.md` status, `lifecycle_stage`) and doctor via the loader.
  This solves the crux: a script can pre-create all lifecycle files at once without
  any stage detector, gate, or savepoint consumer reading a brand-new intent as
  advanced or finished. The intent file (`<id>--<slug>.md`) is never sentineled; it
  is born complete. The match is exact first-line only, so a real file that merely
  contains an HTML comment later is unaffected and a partially-edited sentinel reads
  as real rather than sticking as a placeholder.
- **`scripts/new-intent` (the one-call scaffolding contract).** A single invocation
  allocates the id via `folgezettel-id` (root, or a branch of `--parent`), creates
  `<store>/<id>--<slug>/` plus `actions/` and `resources/`, renders the
  born-complete intent file from `templates/intent.md`, writes the sentinel
  placeholder lifecycle files, wires the reciprocal `[[id]]` links, and
  self-validates with `IntentValidator` (exit non-zero if not born complete). It
  does NOT touch INDEX.md, git, or project creation: those stay in
  `plastic-creating-intent`, which is now a thin wrapper that keeps tier/store
  detection and the branch-vs-root judgement and delegates scaffolding to one
  `new-intent` call.
- **`scripts/hook-create-gate` (PreToolUse, matcher `Write`).** When the target
  path is an intent file inside its own equally-named dir
  (`store/**/<id>--<slug>/<id>--<slug>.md`), it validates the PROPOSED content from
  the hook stdin payload (`tool_input.content`), not the on-disk file (which does
  not exist yet at PreToolUse), using `IntentValidator.validate_content`
  (born-complete frontmatter plus the section structure). It blocks with exit 2 on
  failure. It depends only on the stdin path plus content, never on the auto-bridge
  or `CLAUDE_SESSION_ID`, so it runs unconditionally including in headless and
  background sessions, which dissolves intent 60's D6 objection (the 60-era design
  no-opped without a bridge). If `content` is absent it fails safe and blocks rather
  than allowing a write it cannot validate. It validates only the intent file, never
  the sentinel placeholder lifecycle files. It coexists with the PostToolUse 4a1c1
  backstop in `hook-gate-check`: the PreToolUse block makes the PostToolUse path a
  no-op for the create case, so they never double-report.
- **Section-structure arm on `IntentValidator`.** `SANCTIONED_SECTIONS`
  (`## Intent`, `## Context`, `## Outcome`, `## Insights`, `## Links`, in order)
  plus a pure `validate_sections(body)` flag any unknown top-level `##` heading and
  any missing sanctioned section. `### Decisions` is the only sanctioned `###`
  subsection and is OPTIONAL (added after brainstorming), so its absence is never
  flagged. `validate` folds the section findings into the frontmatter result so the
  CLI and the gate get both checks from one call; the gate, the `validate-intent`
  CLI, and doctor's read-only `section_structure` check all share this one
  definition so it cannot drift.

Portability split (D9): the `new-intent` CLI plus the skill instruction are the
portable lever that works on any harness; the PreToolUse create gate is
Claude-Code-only defense-in-depth, not the primary lock.

## project store provisioning

A project could be registered in `projects.yml` yet have no store on disk, which
left a store-less project that qmd could not register and doctor could only warn
about. Store creation was an inline `mkdir` duplicated across skills. The fix is
one shared definition of store creation that creation and repair both consult.

- **Single source of truth**: `scripts/lib/store_provisioning.rb` is the only
  definition of how a project store is made (mkdir the store at
  `~/.plastic/projects/{slug}/store`, then write-if-missing `.gitkeep`, `INDEX.md`
  from `templates/index.md`, and `project.yml` from `templates/project.yml`). It
  is injectable (`plastic_home`, `package_root`), hermetic, idempotent, uses no
  eval, does no global-constant injection, and performs no qmd mutation, mirroring
  `intent_validator.rb`. The logic was migrated from the orphaned
  `InstallerCore#bootstrap_project_store`, which is now removed.
- **Consumers sit on top of it**: the `scripts/provision-project-store` CLI (exit
  0 on success, non-zero with a report when the slug is unregistered or on usage
  error); the `plastic-creating-intent` and `plastic-creating-project` skills (each
  calls the verb after `projects.yml` registration instead of an inline `mkdir`);
  the `plastic-add-project-store` skill (resolve slug, run the verb, then the
  separate optional `qmd-sync register --store` step); and doctor's read-only
  `project_store_dir` check (warns and is fixable via the verb).
- **Scope boundary**: the provisioner is pure filesystem. It never mutates qmd,
  never edits `projects.yml`, and registration with qmd stays a separate skill
  step that no-ops when qmd is absent.

## worktree provisioning and the delivery lock (intent 73c)

The harness worktree tool assumes the current directory IS the repo root, which
is false for Plastic (cwd is often the parent of the repo subdir). When that
mismatch occurred the tool silently degraded to a feature branch on the shared
checkout, so parallel intent deliveries were not isolated. Plastic supplies its
own isolation instead, deterministic and cwd-independent.

- **Single source of truth**: `scripts/lib/worktree.rb` (module `Worktree`) is
  the only definition of how an intent's worktrees and lock are made. It is
  dependency-injected (a `ShellRunner` runs `git`, a `home` argument resolves
  `projects.yml`), hermetic, idempotent, uses no eval, and does no
  global-constant injection, mirroring `intent_validator.rb` and
  `store_provisioning.rb`. Every git call uses `git -C <resolved path>`, never
  cwd: that is the actual fix for the cwd-not-repo-root gap.
- **Two worktrees, id-first names**: `Worktree.paths` is pure and returns the
  code worktree (`<repo>/.claude/worktrees/{id}--{slug}`, branch
  `plastic/{id}--{slug}`) and the store worktree
  (`<plastic_home>/.worktrees/{id}--{slug}`, branch `plastic-store/{id}--{slug}`).
  `Worktree.repo_for` resolves the abs repo path from `projects.yml` (reusing the
  qmd_sync safe-loader pattern), or nil.
- **Provision and release**: `Worktree.provision(bridge_data)` resolves the slug
  from `bridge_data["intent"]["store"]`, creates both worktrees idempotently (an
  existing worktree path is reused, never re-created or errored), and writes the
  `worktree` block plus `provisioned: true`. It fails open with a stderr log when
  the repo is unresolvable or not a git work tree, setting `provisioned: false`
  and leaving `code: null`. `Worktree.release(bridge_data)` removes both
  worktrees, prunes, and clears the block; it is a no-op when nothing was
  provisioned.
- **The bridge is the lock**: `Bridge.derive` now emits a `worktree` block and a
  `lock` block (both born empty). `arm_auto` stamps the `lock` (owner session,
  `Process.pid`, an acquired-at timestamp, the host) and calls
  `Worktree.provision`; `disarm_auto` calls `Worktree.release`. Both wrap the
  worktree call so a provision or release error never breaks arming or disarming.
  `Worktree.session_live?(pid)` probes liveness with `Process.kill(0, pid)`, and
  `Worktree.lock_held_by_other?` returns true only when another `/tmp/plastic-*`
  bridge for the same intent has a live owner pid that is not the current session
  (a dead owner makes the lock reclaimable).
- **Scope boundary**: `worktree.rb` is pure provisioning and lock-state logic. It
  never edits `projects.yml` and never mutates qmd. The PreToolUse gate that
  blocks edits outside the active worktree, and the cleanup policy that decides
  merge-vs-remove on the completion path, are layered on top by sibling intents.

## living-document

This is a living document. When Plastic's architecture, lifecycle, conventions,
skills, hooks, or harnesses change, this file and `architecture.md` must be
updated in the same change.
