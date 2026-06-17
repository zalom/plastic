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
  manifest (`~/.claude/plastic/manifest.json`) covers agent scripts and hooks. The
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

- **The lifecycle gate runs after the write lands.** The strongest mechanism in
  the framework, `gate-check`, is wired as a PostToolUse hook: it rejects the
  write *after* the file already exists on disk, so a brain that ignores the
  block leaves a half-written artifact behind. It also checks file *presence*,
  never *section form*, so a `spec.md` with the wrong sections passes the gate.
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
with verbs `detect`, `register`, `reindex`, `status`) does all the work by
delegating to the qmd CLI. Each trigger lives at a fixed point:

- **install**: the install skill registers every store as a `plastic-`
  prefixed collection (`register --all`).
- **project creation**: the creating-project skill registers the new project
  store's collection (`register --store <dir>`).
- **intent delivery**: the delivery/completion path reindexes the delivering
  store's collection (`reindex --store <dir>`, which runs `qmd update` then
  `qmd embed -c plastic-<slug>`).
- **session start**: report-only. The boot path may report index status but
  never mutates it.
- **doctor**: a qmd check verifies the integration is healthy, including that the
  ~2GB of models qmd lazily downloads on first embed/rerank are present. The index
  itself lives under `~/.cache` and is never committed to the `~/.plastic` git.

## living-document

This is a living document. When Plastic's architecture, lifecycle, conventions,
skills, hooks, or harnesses change, this file and `architecture.md` must be
updated in the same change.
