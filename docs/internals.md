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
drift. The dashboard is a near-miss on this line: the script owns the
classification, ranking, and data (`dashboard.rb --data` emits a complete,
deterministic JSON payload carrying cell-ready fields for each list, including
the rank-ordered `next_work` list), while the skill composes the human-facing
board from that payload, rendering the four intent lists as Markdown tables and
the wrappers as prose (intent 149, tables in 149a), never re-sorting or
re-classifying. Determinism lives in the payload: the cells arrive pre-escaped
and the list shapes are asserted in tests alongside the untouched text and JSON
goldens.

**Where looseness concentrates.** In the prose skills that produce *written
deliverables*. Determinism is weakest exactly where Plastic ships prose that asks
a brain to author an artifact. The brain-loose 5 are the design and judgement
skills (`intent-brainstorming`, `intent-grilling`) and the curator surfaces
(the `store-curating` skill, renamed from `intent-curator` at 158a while its
agent counterpart `plastic-intent-curator` kept its name, plus
`future-intent-researcher`).
These produce INDEX or cluster reorganizations with no output template at all:
section set, ordering, depth, cluster naming, and orphan thresholds all drift.
`spec.md` moved out of this group at intent 163: `intent-speccing` now owns it
through a fixed eight-section template (`templates/spec.md` plus
`references/per-section-fill-rules.md`), so `spec.md` is no longer the
least-constrained artifact in the framework.

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

Convention today ships in three tiers rather than one file (intent 223). `PLASTIC.md`
(installed at `~/.plastic/PLASTIC.md`) is the always-on core: the small set of rules primed at
every session start, held under 500 lines and 5,000 estimated tokens by a dedicated Minitest
test (`test/plastic_core_budget_test.rb`), the regrowth-enforcement mechanism after two prior
splits (intents 13b, 127) each shrank it once with nothing holding the boundary. Doctrine used
by more than one skill lives in `skills/conventions/` (installed as `plastic-conventions`,
`user-invocable: false`), a thin router skill whose body only names its 8 `references/*.md`
chapters and when to read each. A chapter is reached only through a consuming skill's own bound
load line, `../plastic-conventions/references/<chapter>.md`, resolved relative to the consuming
skill's installed directory; an unbound chapter orphans, and a load line pointing at a chapter
that does not exist is a dangling reference, both caught by the same test. `skill-lint`'s scope
(`skills/*/SKILL.md`) is unchanged by this: it lints `plastic-conventions`'s own body like any
other skill, but it does not read `PLASTIC.md` or enforce the chapter wiring; that enforcement
is the suite test, not doctor, since doctor's skill-lint finding is advisory by design and
always reports pass.

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
rebuildable via `Bridge.rebuild_savepoint`. The `plastic-intent-savepoint` skill is now a thin
reader/verifier, not a writer.

State-from-ledger (intent 81) makes the ledger the read-once answer to "what stage, and is it
done", so a resuming agent reads `savepoint.md` first instead of probing which files exist. The
grammar gains three line classes on top of intent 34's artifact-landing milestones, all keyed by
a `(stage, milestone)` pair for idempotency (`Bridge.savepoint_recorded_pairs`):

- a **born `What` line**, stamped by `new-intent` at creation (not left to a gate firing), so
  even a freshly parked future intent carries the first bookend deterministically;
- **`started` pre-stage lines** (`Why started`, `How started`), appended by the PreToolUse
  `hook-savepoint-pre` the moment a stage's artifact is first written, plus an `Exec started`
  companion emitted by `gate-check` when `checklist.md` lands (How ends, Exec begins, one event);
- a **terminal `Done delivered|abandoned` line**, written by the completion path
  (`Bridge.append_terminal_savepoint`) as the intent transfers into INDEX's Completed/Abandoned
  section. Disposition lives in INDEX (no frontmatter status); the ledger echoes it.

The bookends are fixed and recognizable: the first line is `What created`, the last line is
either the current cycle position or `Done <disposition>`. A consumer classifies from the last
line and then verifies only that line's artifact before continuing. The `started`, `Exec
started`, and `Done` lines are not derivable from files on disk, so `rebuild_savepoint`
deliberately does not regenerate them: a rebuilt ledger is the file-landing skeleton (`created`,
spec, plan, checklist, outcome), which still pins cycle position, while the live ledger carries
the full pre/post detail. The born timestamp is only accurate live, because the intent file's
mtime drifts forward as `## Insights` are appended through the lifecycle.

`revisions.md` is a sibling per-intent ledger, but unlike `savepoint.md` it is neither
auto-written nor part of the deterministic form. The intent-curator authors it by hand during
structural maintenance, recording each move-and-record relocation (the misplaced section, file,
or ref, where it came from, the rule it broke, and its verbatim prior content). It exists only
when maintenance happened, so its presence is itself the signal, and no tool reads or validates
it: it is convention, not enforcement.

The roadmap savepoint ledger (intent 134) mirrors the cycle-step mechanism for roadmaps, which
carried no comparable machine record of their own `## Log`. `scripts/lib/roadmap_savepoint.rb`
(constructor-DI, hermetic: clock and paths injected, no eval, no ENV or global config seam; a
thin `scripts/roadmap-savepoint` CLI wraps it, both registered in `InstallerCore#core_files`)
owns two operations. `append(roadmap_path, event, detail, now:)` writes one line
`<UTC-iso8601>  <event>  <detail>` to the roadmap's name-paired sibling
`roadmaps/<slug>.savepoint.md` (created lazily on first use, moved into `roadmaps/archived/`
alongside its roadmap on close), validated against a controlled vocabulary (`created`,
`dispatched`, `parked`, `merged`, `release`, `handoff`, `closed`, plus optional `added`,
`reordered`, `wave`, `batch`) and keyed for idempotency on the `(event, detail)` pair rather than
the event word alone, since two `dispatched` events with different details are distinct.
`rebuild(roadmap_path)` reconstructs the ledger deterministically from the roadmap's `## Log`:
each `- YYYY-MM-DD HH:MM UTC`-prefixed line opens one event (a continuation line with no date
prefix never matches, so it is inherently ignored for classification), classified by a small
ordered keyword table and converted to iso8601 with `:00Z` seconds, then cross-checked against
the roadmap's grouping section (`## Batches`, or legacy `## Waves`) and the tier's INDEX
`## Completed` section so every `delivered` batch entry with no
matching `merged` line in the Log gets one backfilled from INDEX, timestamped only from an
on-disk source and never invented (an entry with no recoverable source anywhere is silently
dropped, not fabricated). The `plastic-roadmap` skill's verbs call `append` at the same
closing-step slot each already uses for its QMD reindex; `plastic-roadmap-continuing` reads the
ledger's last line as a cheap last-event signal, purely as a read. `INDEX.md` stays the single
status writer throughout; the ledger, like the intent-dir one, is sugar, never a source of truth.

The roadmap read path (intent 148) sits on top of that ledger. `scripts/lib/roadmap_queue.rb`
(`RoadmapQueue`, constructor-DI and hermetic: clock and paths injected, no eval, no ENV or global
config seam; a thin `scripts/roadmap-next` CLI wraps it, both registered in
`InstallerCore#core_files` and covered by a hermetic test) is the one reader the auto loop and
`plastic-roadmap-continuing` share. It does two things: liveness-ranks the tier's `roadmaps/*.md`
(a `delivering` or `blocked` entry wins, else the newest ledger or `## Log` timestamp, read
through `RoadmapSavepoint.ledger_path_for`), and within the winning roadmap selects the frontier
batch. The frontier batch is the first batch, top to bottom, holding a `queued` or `delivering`
entry; that batch's `queued` entries in file order are dispatchable (the head is next), a
`delivering` entry marks the batch in-flight and gates the next batch, a `blocked` entry is surfaced
but does not gate, and `delivered`/`abandoned` entries are settled. Every frontier token is
reconciled against INDEX.md before classification and INDEX wins on any mismatch, so an intent
INDEX already shows Completed or Abandoned can never be dispatched. The CLI emits JSON with a
`state` field (`dispatchable`, `in_flight`, `exhausted`, `none`, or `tie`) and a
`dispatchable_queue` array shaped to match the dashboard's, plus `in_flight`, `blocked`, and
`tie_candidates`. It runs in two modes: queue mode (the default, for the loop) breaks ties
deterministically (newest ledger line, then slug ascending) and flags `tie: true`; which mode
(`--which`, for `plastic-roadmap-continuing`) returns `tie_candidates` so the skill's single ask
resolves the tie. The design is file-based throughout (roadmap `.md`, the 134 ledger, INDEX.md),
DB-ready but not DB-dependent: `RoadmapQueue` is the single seam a future 147 DB-backed read
swaps behind without changing either caller. A sibling seam covers ranking itself: dispatchable
candidates are value-ordered by an injected `ranker:` (default `FileOrderRanker`, today's file
order), reported as `ranking_strategy` in the payload, so intent 173's decision-systems
recommendation can replace the ordering rule without reworking parsing, frontier detection, or
the rest of the JSON contract.

A companion rule keeps the intent-dir ledger itself honest. `Bridge.savepoint_phantom_lines`
(intent 134) is pure and disk-only, no bridge or session resolution and no writes, matching
intent 52's decoupling precedent: it flags a `savepoint.md` line that disk evidence contradicts,
in three classes: a file-landing milestone (built from the same map `savepoint_milestone` uses)
whose file is absent or still a sentinel placeholder; a duplicate `(stage, milestone)` pair (the
later occurrence is the one flagged); or a state line, `How  started` or `Exec  started`, whose
stage prerequisite (the PRECEDING stage's real artifact, not its own, since a `started` line
legitimately fires before its own stage's file is real) is absent on disk. The bug-131 bridge
clobber and the 124a out-of-band merge are the two live precedents this guards against: either
can leave a phantom or dropped line that nothing previously detected. The
`plastic-intent-savepoint` skill's verify step runs the detector and, on a hit, auto-rebuilds via
`Bridge.rebuild_savepoint` for a live (INDEX Active) intent; for a terminal (Completed/Abandoned)
intent it reports and stops, since completed intents are immutable, and the 124a manual
Done-bookend repair (rebuild the skeleton, then re-append the terminal line from git or mtime
evidence) stays reserved for an explicit human grant. `doctor.rb`'s `check_done_signals` carries
a sibling `savepoint_truthful` advisory (pass when clean, warn and never fail, mirroring
`signals_complete`) that runs the same detector across every intent dir the check already visits.

Some `savepoint_operational` gaps can never legitimately close: a terminal intent with no real
`outcome.md` has no disposition to echo, and 219 D6 forbids ever inventing one, so the warning
would otherwise recur forever. Intent 274 gives each store a `doctor-exclusions` file, sibling to
that store's `INDEX.md` (`~/.plastic/doctor-exclusions` globally,
`~/.plastic/projects/<slug>/doctor-exclusions` per project), recording knowingly-exempt
`(intent_id, rule)` pairs. The format
is `/etc/hosts`-shaped: one `rule_name id id id` line per rule, blank lines and `#` comments
ignored, duplicate rule lines unioned. It is a plain-text config table, not a markdown document
(no `.md` extension), and it never ships in the npm package: `scripts/lib/rule_catalog.rb`
(`RuleCatalog::EXCLUDABLE_CHECKS`, one key in v1, `savepoint_operational`) is the vocabulary of
doctor check names an exclusion file may name, and `scripts/lib/doctor_exclusions.rb`
(`DoctorExclusions.load`/`.parse`/`.rules_for`) is the pure-parse-plus-thin-IO loader, never
raising. A missing file is the normal case (zero exclusions, zero errors, identical to before
this file existed); a malformed line contributes one error naming its line number and excludes
nothing (fail milder than the bug: a typo must never silently suppress a real regression); any
loader error forces `savepoint_operational` to `warn` with the error text in `details`, so a
broken exclusion file is loud rather than silently permissive. `check_done_signals` loads one
exclusion file per store and routes a suppressed `savepoint_operational` finding to a dedicated
`:excluded` bucket inside `done_signal_findings_for_dir` rather than a post-filter over rendered
`details` strings (keeping intent 222's single-source-of-truth guarantee intact); the key is
`(intent_id, rule)`, never bare `intent_id`, so excluding `savepoint_operational` for an intent
has no effect on `signals_complete`'s independent report for that same intent. The check's
message always folds in the honest count and the file's path once any exclusion applies, and
reaches `pass` once every remaining gap is excluded. `RuleCatalog::REVISION_RULES` shares the
same file as a second, unrelated axis: the `[rule: <tag>]` vocabulary every `revisions.md` entry
carries (see the maintenance-and-revisions reference). It is enforced by
`test/rule_catalog_test.rb`, never at `RevisionsWriter` runtime, because a receipt writer that
refuses to write on an unrecognized tag would fail harder than the bug it is meant to catch.

`scripts/maintenance-run --tool register-exclusions [--rule <name>] [--store <key>] [--apply]`
is the one-time population tool (197-conformant, dry-run by default): it computes violations by
calling `Doctor#done_signal_findings_for_dir` directly, the same function `check_done_signals`
itself calls, so the registry can never disagree with the checker about what counts as a
violation. It processes every store in one invocation by default (all stores already live in
the single `~/.plastic` git repo, so a cross-store write is still one repo and one scoped
commit), unions with any existing hand-edited file content so a manually added id is never
dropped, and skips (never aborts on) any intent dir holding a fresh delivery lock, reporting the
skip. It writes no `revisions.md` entries: the tool modifies no intent directory, only one
store-level table per store, so 197's receipt-before-write rule (which covers tools that
structurally edit an intent's own files) does not apply here, and writing one would mean editing
every touched Completed intent directory, which the standing rule that completed intents are
immutable forbids. The scoped git commit plus the diffable exclusion file itself are the receipt.

Session resolution feeds the bridge that the gate hooks read (intent 52). Claude Code does
not export a session id env var into the hook environment; it passes `session_id` on the hook
stdin JSON. So the bash wrappers parse `session_id` out of stdin (in Ruby, never in bash) and
hand it to the gate scripts as a second argument. `Bridge.resolve_session` then takes the
first non-empty of three sources, in precedence order: the explicit stdin `session_id`, the
`CLAUDE_CODE_SESSION_ID` environment variable, and a derived `auto-<digest>` key
(`Bridge.derive_key`, a short SHA256 of `store/intent_id`). The derived key is deterministic,
so a session-less arm and a later session-less gate-check resolve to the same bridge file
instead of writing `plastic-.json` with a null session. `Bridge.write` now refuses an empty
session, so a null-session bridge can never be persisted.

The savepoint write is decoupled from bridge resolution (intent 52). `hook-gate-check` derives
the intent directory straight from the written file path via `Bridge.intent_dir_for` (it walks
up to the first ancestor matching `.../store/<id>--<slug>`) and appends the savepoint there
BEFORE any bridge lookup. A missing bridge, an unset session, or a headless background run can
no longer skip the ledger. Bridge discovery is strictly per-session (intent 90): `Bridge.discover_bridge`
prefers an exact-session match, and when the caller `session` is present it keeps ONLY
candidates whose own `session` equals the caller (own-session, and the derived-key headless
case reduces to the same equality). A foreign session's bridge is never resolved; when the
caller has a session and owns no bridge, discovery returns `nil` so every gate fails open
(no-op) for that session instead of inheriting another session's armed intent. Before that per-session filter, one opt-in carve-out (intent 168) applies only when hook-code-gate passes `edited_path`: if the edited file lies inside a provisioned code worktree (`<repo>/.claude/worktrees/{id}--{slug}`), discovery resolves the candidate whose `worktree.code` owns that directory (newest mtime on a tie), or `nil` when none owns it, and never the session-matched sibling. Every other caller passes no `edited_path`, so its resolution is unchanged. With a session
present, cwd/store narrowing is a hard filter (a non-matching store excludes the candidate,
never reverting to the unfiltered pool). Only when the caller has NO session at all (the
intent 52 headless / derived-key path) does it keep the degraded scan of `/tmp/plastic-*.json`:
valid bridges only, preferring auto-armed ones, then those whose `intent.store` matches the
current working directory, breaking ties by newest mtime, with the best-effort cwd revert
retained so a lone armed bridge is still found. This fixes the cross-session freeze (intents
49, 66) that intent 79 (exact-match keying) and intent 80 (terminal cleanup) deliberately left
in the fallback. The `/tmp` directory is injectable so the scan is testable against a fake
directory.

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

The `## Active` line shape that scan depends on is load-bearing. `Bridge.intent_active?`
matches a line shaped like `` `- [ID <sep> Title](path)` ``, where `<sep>` is either a real
em dash (U+2014) or a plain hyphen, as the id/title separator on READ, through the
single shared matcher `Bridge.index_entry_match` (`Bridge::INDEX_ENTRY_RE`), the same one
`scripts/end-intent`'s own INDEX-move parser uses (intent 188). Before intent 188, a plain
hyphen line made `intent_active?` return false, which failed the lock gate OPEN: an intent
that was genuinely active read as not-active, its bridge became purge-eligible, and writes
stopped being gated for it; intents 96 and 169 both flagged this and deliberately deferred
hardening it, since accepting a hyphen changes fail-open behavior and deserved its own
decision rather than a silent widening. Intent 188 makes that decision: hardening
`intent_active?` is strictly MORE blocking than before (a hyphen-formatted `## Active` line
is now correctly gated instead of silently ignored), accepted as a bug fix since no passing
test relied on the old fail-open behavior. Every WRITE still emits the real em dash; only
what the readers can PARSE has widened.

The `plastic-intent-continuing` skill consumes that ledger on the resume path (intent 36): when the
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
  `plastic-intent-continuing` skill also calls it on resume.

- **Full run (no flag)**: three-state. Walks every check category (global store,
  conventions across all intents, agent registration, core files, project stores,
  deprecations, runtime). This is what `/plastic-doctor` invokes. It also runs automatically
  after every `plastic-update` (informational: prints the report but does not block
  or revert the update).

The `runtime` category holds one check, `ruby_floor`: it spawns bare `ruby` the way a hook
launcher does and asks the resolved interpreter for its own version and absolute path. It
passes when that version is at or above `Preflight::RUBY_FLOOR`, and it warns in two cases:
when the version is below the floor, and when no runnable `ruby` could be resolved at all
(undetermined, for example an unparseable version string). It never fails the run. It exists
because a version manager that activates on shell prompt render does not reach a hook process
spawned by the agent application, so the ruby your shell has is not always the ruby your hooks
get. The check reports only. It never pins an interpreter and never repairs.

The project-stores category includes an additive `project_store_dir` check
(intent 61): when a registered project's `store/` directory is missing, it warns
and is fixable, with the fix `provision-project-store {slug}`. Doctor stays
read-only; the doctor skill applies the fix by running the verb.

`plastic-feedback` (intent 174) follows the same engine-in-lib, thin-CLI shape as
`doctor.rb`: `FeedbackReport` in `scripts/lib/feedback_report.rb` is a constructor-DI
engine (redact secrets, fill the version token, resolve a collision-safe report
path, cap the encoded URL at 7500 bytes with a page-one-plus-marker overflow), and
`scripts/feedback-report` is the thin CLI the skill shells out to. The skill sets
`disable-model-invocation: true` so only the user can fire it; a one-line nudge in
`PLASTIC.md` is the only surviving trigger path for the agent, since that flag also
hides the skill's description from the agent's own context.

`hook-session-start` calls `--core` in-process (reusing the `Doctor` class, no second
process spawn) to drive the boot banner on every session start (intent 36a).

The hook surfaces that banner on two channels from a single `BootBanner` renderer (intent 54):
`hookSpecificOutput.additionalContext` (added to the model's context) and the top-level
`systemMessage` (rendered in the user's terminal, and re-fired on `/clear`). The banner is
binary: success produces one line, error produces one line with a prompt to run
`/plastic-doctor`. Sharing one renderer means the visible line and the model-facing line
cannot drift.

`hook-continue` follows the same two-channel shape for the dashboard (intent 125): it keeps
its existing `additionalContext` cockpit dump unchanged, and now also emits a top-level
`systemMessage` one-line summary (counts, and the next big thing when there is one) from a
pure `DashboardBanner` renderer. It degrades silently on any failure (subprocess, JSON,
renderer), so a broken or slow dashboard call never crashes `UserPromptSubmit`.

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
- **project creation**: the project-creating skill registers the new project
  store's collection (`register --store <dir>`).
- **intent delivery**: the delivery/completion path reindexes the delivering
  store's collection. This is the LAST step of the canonical End tail (intent
  93): it runs after the INDEX terminal move, the savepoint `Done` line, the
  commit, and disarm (worktree release, `Lock.release`, then the bridge purge),
  so the index never references a bridge or lock that disarm is about to remove.
  It is mandatory on completion and runs async
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

The power-tools `UserPromptSubmit` hook (`hooks/power-tools` ->
`scripts/hook-power-tools`, decision logic in `scripts/lib/qmd_hook.rb`) runs on
every turn and emits one thing: the recommendation string from
`scripts/lib/power_tools.rb` (`PowerTools.mandate`), a "prefer QMD" reminder for
finding intents when qmd is present and a "prefer Serena's symbolic tools"
reminder for code navigation when Serena is present, or, when Enola is also
present, that slot names Enola instead of Serena (Enola-first, one code-navigation
slot; `PowerTools.enola?` checks a `.enola` marker or `enola` on PATH). When qmd
and a code-navigation tool are both present, the two collapse into ONE combined
line naming both, not one line per tool. Serena presence is detected by a
`.serena` marker in the working directory or an ancestor, or `serena` on PATH
(`PowerTools.serena?`); qmd presence by `PowerTools.qmd?`. These are
recommendations, not mandates (intent 108, D8): the agent is reminded, never
obliged. All three probes are PATH and marker-file walks
with no subprocess, so the whole hook costs about a tenth of a second. A 2s timeout
plus rescue-all keeps anything unexpected from blocking the turn; when no tool is
present the hook is a silent no-op. It registers as a fourth `UserPromptSubmit`
entry in `merge_claude_hooks`, ships via `core_files`, and its launcher is covered
by doctor's `HookRegistry`-derived hook checks.

Until intent 246 this hook also injected scored `qmd search` hits ahead of the
mandate, gated on a substantive prompt. Intent 225 measured that injection at 0.24
intent-level recall@3 against a plain ripgrep control at 0.18, while agent-driven
`qmd query` scored 0.71, and both of the hook's expensive subprocesses lived inside
that block. It was removed because the failure was recall, not latency, which is
also why caching and async were rejected. `QmdSync.search` is untouched and still
backs the read-only `scripts/qmd-sync search` CLI verb.

### intent born-complete validation

An intent can be born missing a required frontmatter field (intent 51 was created
with no `chain` key, and nothing caught it until a later doctor run). The fix is
one shared definition of "born complete" that creation and diagnosis both consult.

- **Single source of truth**: `scripts/lib/intent_validator.rb` is the only
  definition of born-complete (required fields present, `sources` and `chain`
  well-formed arrays of id references (bare ids, or cross-store references like global:1a2)). It is injectable (`plastic_home`), hermetic,
  uses no eval, and does no global-constant injection, mirroring `qmd_sync.rb`.
- **Three consumers sit on top of it**: the `validate-intent` CLI (exit 0 when
  complete, non-zero with a report otherwise); the `plastic-intent-creating`
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
bypass `plastic-intent-creating` and hand-author intent files with the same Write
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
  `plastic-intent-creating`, which is now a thin wrapper that keeps tier/store
  detection and the branch-vs-root judgement and delegates scaffolding to one
  `new-intent` call.
- **create-gate (PreToolUse check, applies to Write plus Edit plus the
  Serena MCP edit tools, per `HookRegistry::GATE_TOOLS["create-gate"]`).**
  On Claude it runs as one of five in-process checks inside the merged
  `scripts/hook-edit-gates` dispatcher (intent 244); on Codex it runs the same
  way inside `scripts/lib/codex_edit_gates.rb` (intent 251), add-only there
  (Update, Delete, and Move defer to the PostToolUse backstop).
  `scripts/hook-create-gate` is retained as a thin CLI wrapper over the same
  `EditGates.create_gate` logic, with no production caller on either harness
  anymore, kept as the isolation surface `test/create_gate_hook_test.rb`
  drives directly. When the target
  path is an intent file inside its own equally-named dir
  (`store/**/<id>--<slug>/<id>--<slug>.md`), it judges the payload with
  `IntentValidator.validate_content` and blocks with exit 2 on failure. Three
  payload shapes (intent 108): a Write validates the PROPOSED
  `tool_input.content`; an Edit simulates the replacement (`old_string` to
  `new_string`, `sub` or `gsub` per `replace_all`) against the on-disk file and
  validates the RESULT, blocking when the file does not exist; a pathless MCP
  mutation validates the CURRENT on-disk file (a valid file passes, since the
  PostToolUse backstop validates the result; a missing or invalid one blocks).
  It depends only on the stdin path plus payload, never on the auto-bridge
  or any session id, so it runs unconditionally including in headless and
  background sessions, which dissolves intent 60's D6 objection (the 60-era design
  no-opped without a bridge). It validates only the intent file, never
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

## The four delivery scripts (intent 213)

`AGENTS.md` states the classification rule: a step becomes a script only when its output is
a pure function of already-committed artifacts (spec.md, plan.md, checklist.md, outcome.md,
test results, the diff). Everything else stays judgment and stays with the agent. Four
scripts, each a thin CLI over its own `scripts/lib/` module, apply that rule to the four
lifecycle steps that qualify.

`scripts/start-intent` composes `Bridge.arm_auto` or `Bridge.arm_guided`, then reads the four
lifecycle files and prints a resume-station report. It never releases or takes over a lock.

`scripts/scaffold-intent` is one CLI with three subcommands, `spec`, `checklist`, and
`outcome`. Each writes only what is mechanically derivable from a committed artifact and
leaves every judgment section as the template's stub. It never scaffolds `actions/`. Running
the `outcome` subcommand makes the derived stage read as done, so run it only at the true end
of Exec.

`scripts/verify-intent` folds doctor scoped to the intent, the added-line em-dash diff guard
(the first standing implementation of that check), a diffstat, and an optional
caller-supplied suite command into one verdict. It does not invent a project test-command
config.

`scripts/exec-worktree` wraps `Worktree.finish`. Its only net-new logic is an order
precondition that calls `Bridge.code_gate_decision`. The precondition is a friendly early
error, not the enforcement point: the hook layer remains the gate, and on a guided bridge the
precondition is advisory only.

`scripts/lib/spec_header.rb` is the only parser of the `Tier:` and `Settled:` lines at the
top of spec.md. `Bridge.savepoint_tier` delegates to it.

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
  error); the `plastic-intent-creating` and `plastic-project-creating` skills (each
  calls the verb after `projects.yml` registration instead of an inline `mkdir`);
  the `plastic-store-provisioning` skill (resolve slug, run the verb, then the
  separate optional `qmd-sync register --store` step); and doctor's read-only
  `project_store_dir` check (warns and is fixable via the verb).
- **Scope boundary**: the provisioner is pure filesystem. It never mutates qmd,
  never edits `projects.yml`, and registration with qmd stays a separate skill
  step that no-ops when qmd is absent.

## per-agent model resolution and installer application (intent 116)

Every subagent in `agents/*.md` pins an explicit Claude Code model alias (`opus`,
`sonnet`, or `haiku`) in its own frontmatter, tiered by role: `plastic-enforcer`,
`plastic-brainstorming`, and `plastic-planner` are `opus`; `plastic-spec-specialist`,
`plastic-executor`, `plastic-intent-curator`, `plastic-future-intent-researcher`, and
`plastic-intent-discovery` are `sonnet`. None is ever `inherit` and none is ever
Fable by default. Fable is named in three places, and only three: the auto-mode advisory
notice below (about the human's main session, never a dispatched subagent), an
explicit `agents.models.<name>` config override, which is honored as written for a
dispatched subagent when one is configured (e.g. `plastic-brainstorming: fable`,
mihradesign intent 24, a sanctioned, permanent override, not drift), and the shipped
default of one of the two consultation agents (`plastic-advisor`; its sibling
`plastic-faux-advisor` ships `opus`, not Fable). The two advisors, `plastic-advisor`
and `plastic-faux-advisor`, are not lifecycle stage roles: the never-Fable rule governs
stage agents only. Neither is ever dispatched by the auto pipeline; they are
consultation roles summoned deliberately by the user or the main session, and their
models are user configuration (fable and opus by default on Claude Code).

- **Single source of truth for the tier table**: `scripts/lib/agent_models.rb` holds
  `AgentModels::TIER_DEFAULTS`, a pure Ruby hash mirroring the shipped frontmatter
  (basename without `.md` to alias). It has no file IO, no `ENV`, no `eval`. It also
  exposes `AgentModels.override_map(project_config:, global_config:, harness:)`, a
  pure resolver that merges `agents.models.*` out of a global config hash overlaid by
  a project config hash (project wins), scoped to `harness` ("claude" or "codex"),
  returning ONLY the configured overrides. `AgentModels.models_section(config, harness:)`
  implements the scoping: for `harness: "claude"` it merges the legacy flat scalar
  entries with the `claude` sub-hash (nested wins for the same agent); for any other
  harness it reads ONLY that harness's own nested sub-hash, never the flat entries and
  never another harness's sub-hash. Both deliberately exclude the tier defaults,
  because a rewrite to a value the shipped file already has would violate "no override
  configured leaves the frontmatter untouched."
- **Config key and precedence**: `agents.models.<basename>` in a project's
  `<dir>/.plastic_store/config.yml` or the global `~/.plastic/config.yml` overrides
  one agent's tier, honoring the same `project -> global -> built-in default`
  precedence `read-config` already applies to every other key.
  `scripts/read-config` seeds `DEFAULTS["agents"]["models"]` from
  `AgentModels::TIER_DEFAULTS` (requiring `lib/agent_models` rather than re-typing the
  table), so `read-config agents.models.plastic-executor` answers `sonnet` out of the
  box and honors an override the same way any other dotted key does.
  `templates/config.yml` documents the key as a commented example so a user does not
  need to read source to find it.
- **Installer applies the override at copy time**: `InstallerCore#install_agents`
  takes an injected `models: {}` map (`{ "plastic-executor" => "sonnet" }`, keyed by
  basename without `.md`) and, per copied file, checks for an override. With one, it
  rewrites the single frontmatter `model:` line via a targeted regex substitution
  (`rewrite_model_line`, the same `content.gsub`-style idiom `install_claude` already
  uses for its hook path rewrite, not the array-only `FrontmatterWriter`); with none,
  it plain-copies the file so the shipped value passes through unchanged. The
  `agent_model_overrides(project_dir = nil, harness: "claude")` helper resolves
  project-then-global config into an `AgentModels.override_map` scoped to `harness`
  (loading YAML defensively via `load_config_yaml`, tolerating a missing or malformed
  file). `install_claude` and `install_hermes` call `install_agents` with `models:
  agent_model_overrides` (default claude scope), so the override lands identically
  for those two harness targets on install, update, and repair. `install_codex`
  instead calls `generate_codex_agents` with `models: agent_model_overrides(harness:
  "codex")` (intent 102a, rescoped at intent 185, model mapping added at intent 186):
  Codex reads standalone `~/.codex/agents/<name>.toml` files, not the `.md` frontmatter
  format, so a tier alias (opus, sonnet, haiku) resolves to BOTH a `model` line (from
  `AgentModels::CODEX_MODEL_BY_ALIAS`, model first) and a `model_reasoning_effort`
  line, a literal override resolves to a `model` line only, and an empty value emits
  nothing (the agent inherits the session model). Scoping the Codex call to `harness:
  "codex"` is what closes the literal-model-id leak: a value set under the legacy flat
  form or `agents.models.claude.*` is claude-scoped only and is never visible to the
  codex-scoped resolution, so it can never surface in a generated Codex TOML `model`
  line. See [harness-adapters.md](reference/harness-adapters.md) for the full codex
  agent TOML contract.
- **Dispatch-time contract (belt-and-braces)**: because Claude Code reading
  frontmatter at dispatch time is a harness implementation detail rather than a
  contract Plastic controls, every dispatch site (the enforcer's per-stage
  dispatches, `skills/auto/SKILL.md`'s dispatch mechanics, the
  `plastic-intent-discovery` dispatch inside `plastic-intent-starting`, and the
  `plastic-project-continuing` stale-future-intent triage's dispatch of
  `plastic-future-intent-researcher` (which does not itself spawn further
  sub-agents)) also resolves the target agent's model through the same chain
  (`read-config agents.models.<basename> --project <repo>`) and passes it
  explicitly as the dispatch call's model parameter, never relying on the
  dispatched role's frontmatter alone.
- **Orchestrator advisory (not a gate)**: at auto-mode start, the enforcer and the
  `plastic-auto` skill each recommend once that the user run the orchestrating main
  session on the best available thinking model (Fable, Opus, or whatever supersedes
  them), for the sharpest gating and synthesis. This changes no behavior and blocks
  nothing if ignored; it concerns only the human's main session, since dispatched
  subagents keep their pinned tier and never resolve to Fable, unless an explicit
  `agents.models.<name>` config override names Fable for that role, in which case the
  override is honored as written. The two advisors, `plastic-advisor` and
  `plastic-faux-advisor`, are not lifecycle stage roles: the never-Fable rule governs
  stage agents only. Neither is ever dispatched by the auto pipeline; they are
  consultation roles summoned deliberately by the user or the main session, and their
  models are user configuration (fable and opus by default on Claude Code).
- **What-stage discovery agent**: `plastic-intent-discovery` (paired with the
  `skills/intent-discovering/SKILL.md` workflow) closes the What-stage gap in the
  one-agent-per-stage table. It fires inside `plastic-intent-starting`, right after
  an intent is activated (moved from `## Future` to `## Active`) and the bridge is
  armed, running under that lock as the owner session (it does not acquire the
  lock itself and is not blocked by it): it reads the intent's `chain`/`sources`
  frontmatter, runs QMD-first
  discovery across completed predecessor work and related parked or future intents,
  and deposits its findings to `resources/discovery--<slug>.md` in the intent
  directory ONLY. It never writes the intent file, `spec.md`, or any other lifecycle
  deliverable, so the lock-owner-only write rule stays intact; the Why-stage
  `plastic-brainstorming` agent is the one that reads the deposit and enriches
  `## Context`.

## worktree provisioning and the delivery lock (intent 73c)

The harness worktree tool assumes the current directory IS the repo root, which
is false for Plastic (cwd is often the parent of the repo subdir). When that
mismatch occurred the tool silently degraded to a feature branch on the shared
checkout, so parallel intent deliveries were not isolated. Plastic supplies its
own isolation instead, deterministic and cwd-independent.

- **Single source of truth**: `scripts/lib/worktree.rb` (module `Worktree`) is
  the only definition of how an intent's worktree and lock are made. It is
  dependency-injected (a `ShellRunner` runs `git`, a `home` argument resolves
  `projects.yml`), hermetic, idempotent, uses no eval, and does no
  global-constant injection, mirroring `intent_validator.rb` and
  `store_provisioning.rb`. Every git call uses `git -C <resolved path>`, never
  cwd: that is the actual fix for the cwd-not-repo-root gap.
- **One worktree, id-first name**: `Worktree.paths` is pure and returns the
  code worktree (`<repo>/.claude/worktrees/{id}--{slug}`, branch
  `plastic/{id}--{slug}`). A paired store worktree used to exist; intent 178
  retired it, and store-write safety for lifecycle docs now comes from intent
  197's branch-from-main plus scoped-commit mechanism.
  `Worktree.repo_for` resolves the abs repo path from `projects.yml` (reusing the
  qmd_sync safe-loader pattern), or nil.
- **Provision and release**: `Worktree.provision(bridge_data)` resolves the slug
  from `bridge_data["intent"]["store"]`, creates the code worktree idempotently
  (an existing worktree path is reused, never re-created or errored), and writes
  the `worktree` block plus `provisioned: true`. It fails open with a stderr log
  when the repo is unresolvable or not a git work tree, setting `provisioned:
  false` and leaving `code: null`. `Worktree.release(bridge_data)` removes the
  worktree, prunes, and clears the block; it is a no-op when nothing was
  provisioned.
- **Unified `PLASTIC_HOME` seam** (intent 169): every CLI-script and hook entry
  point resolves its sandbox override from the single env var `PLASTIC_HOME`
  (`read-config`, `dashboard.rb`, `qmd-sync`, `provision-project-store`,
  `validate-intent`, `doctor.rb`, `install.rb`, `hooks/check-update`); an older,
  differently-named env var that only `read-config` read was hard-cut, not
  aliased. Holding this seam is a level mismatch: the env var names the
  plastic_home ROOT (`~/.plastic`) and is
  used directly as `File.join(PLASTIC_HOME, "store")`, while `worktree.rb`'s
  `home:` kwarg names the OS HOME (the PARENT of `.plastic`) and computes
  `plastic_home = File.expand_path(File.join(home, ".plastic"))` internally, so
  threading the env value straight into `home:` would yield a
  `~/.plastic/.plastic` bug. `Worktree.provision` therefore never reads the env:
  it derives `home` from the already-sandboxed `bridge_data["intent"]["store"]`
  path (anchored on the `.plastic` path segment, via the pure `home_from_store`
  helper), falling back to its `home: Dir.home` default only when the store is
  blank or unrecognized. This closes a real incident where a sandboxed board,
  with no override on `provision`, planted a git worktree in the operator's
  actual `~/.plastic`; deriving from the store trusts the already-sandboxed
  value over the ambient environment. The derivation only engages when the
  store's plastic-home segment is literally named `.plastic` (a sandbox home
  like `/tmp/x/.plastic` works; an arbitrarily named root does not, and
  `provision` falls back to the passed `home:`).
- **The lock file is the truth, the bridge is a cache** (intent 108):
  `scripts/lib/lock.rb` owns the durable `delivery.lock` JSON file inside the
  intent directory. `owner_session` is authorization; the controller's
  `harness`, `agent`, `model`, `thread`, and `mode` are descriptive provenance
  supplied explicitly by the harness. Missing legacy values remain unknown and
  are never reconstructed from transcript locations, session-id formats, or
  other heuristics. The file never carries a pid. `Lock.acquire` is atomic
  (O_EXCL) and returns
  `:acquired/:owned/:held/:stale/:excluded/:corrupt`; freshness is the file
  mtime against `Lock::TTL_SECONDS` (1800 seconds), refreshed by
  `Lock.heartbeat` from the write-path hooks (`hook-gate-check` and the
  lock-gate allow path). The mtime is the sole heartbeat and freshness truth;
  provenance timestamps are descriptive only. `arm` acquires the lock, raising
  `Bridge::LockHeldError` with the resolving `plastic-lock` verb when it
  cannot, and fills the bridge's `lock` block as a cache; `disarm_auto`
  releases the worktrees, clears the lock, and only then is the bridge
  purge-eligible (`purge_done_bridges` also skips any bridge whose intent dir
  still holds a `delivery.lock`). This makes the post-done access window
  lock-bounded, `[INDEX terminal to Lock.release]` (intent 93): while the lock
  is held the completing session keeps full read and write access to the
  terminal directory and no purge can fire, and once `Lock.release` runs the
  window closes, the bridge is purged, and the directory is frozen. A crash
  mid-tail is recovered by reclaiming the stale lock and finishing the tail;
  `doctor` (the `done_signals` check) surfaces this as a stalled completion
  (terminal in INDEX but the lock is still present or stale). Finishing the tail
  is finishing a completion, never a reactivation: a done intent is never moved
  back to `## Active`. Gates decide from the lock file:
  `Bridge.lock_gate_decision` reads the TARGET intent dir's lock, admits the
  owner or a registered delegate (even on a stale lock, which stays its
  owner's until an explicit takeover), and every deny names the resolving
  command. Rearming the same session preserves authority and refreshes supplied
  provenance. A stale foreign lock is taken only by `Lock.takeover`, which
  replaces the controller and appends an audit line to the intent's savepoint.md.
  `Worktree.lock_held_by_other?` asks the same file, so `/tmp` bridges are
  never consulted for ownership and no code probes a pid.
  `Bridge.repair_lock` is the one idempotent repair: it rebuilds the lock and
  the bridge cache from disk, migrates legacy pid-stamped bridges, and never
  touches a fresh foreign lock. It also provisions the worktrees the same way
  `arm` does (intent 136), so a repaired bridge always carries `worktree.code`
  instead of wiping it back to derive's unprovisioned default; `plastic-lock
  fix`, `plastic-lock reclaim`, and the boarding skill's self-heal all inherit
  this since they call `repair_lock`. The `plastic-lock` CLI exposes it
  (verbs: who, status, fix, release, reclaim, delegate). `who` reads only the
  durable lock, its mtime, and claim files. It never repairs state, consults the
  bridge, or searches harness transcripts.

- **Three distinct evidence layers and bounded delegate history** (intent 108a):
  the controller record proves whole-intent authority; a registered delegate record
  authorizes one child session under that controller; a claim record identifies
  one current writer for one artifact among already-authorized sessions. Delegate
  activity status (`active`, `finished`, or `failed`) is observational and does not
  remove the session from the string-array authorization list. A delegate remains
  authorized until a separate removal mechanism exists. Finished and failed activity
  history is capped at the 20 most recent terminal entries.

- **Solo-mode advisory relaxation** (intent 128): `Bridge.lock_gate_decision`
  and `Bridge.worktree_gate_decision` are ARBITRATION gates, not the
  stage-ordering gate, so they only matter when a second writer might exist.
  `Bridge.solo_delivery?(scan_roots:, session:, ttl:, now:)` scans the durable
  `delivery.lock` files under the injected `scan_roots` (dependency-injected,
  no ENV seam) and returns true only on a positive, confident solo
  determination: exactly one fresh lock across the scan, owned by `session`,
  with an empty `delegates` array. More than one fresh lock (even several
  under the same `owner_session`, which still counts as parallel-in-play), a
  foreign owner, a non-empty `delegates` array, a blank/unresolvable session,
  or any scan error all return false, preserving today's fail-closed behavior.
  Both gates compute this once (scan roots: the target intent's store plus the
  global store under an injected `home:`) and, on a confirmed solo, return
  `nil` (allow, with one terse stderr line) at every arbitration deny point
  instead of the deny string. `code_gate_decision` (the stage-ordering gate)
  and `Claim.claim_gate_reason` (the per-artifact claim gate) are never
  touched by this: a solo context still enforces How before code edits, and
  the claim gate's single-writer guarantee is unaffected.
  Two hardenings keep the detection strictly conservative. First, a fresh
  lock file that fails to parse (corrupt) is real ambiguity, not an absence:
  `solo_delivery?` treats any unreadable-but-fresh lock as disqualifying,
  never as a lock to silently drop from the count. Second,
  `worktree_gate_decision`'s scan_roots always include the EDIT TARGET's own
  store, not just the acting bridge's own store plus the global store, so a
  live rival lock on an intent in a different project is never invisible to
  the scan just because that project is not the acting session's own; this
  makes rule 2 (non-owner store edit) fail-closed against cross-project
  rivals too. Both changes only add scan coverage or narrow the true-case, so
  they can only make solo detection stricter, never looser.

## per-artifact claim tokens (intent 111)

The delivery lock above resolves ownership at the whole-intent grain: it answers
who may work an intent at all, not who may write one specific lifecycle file
right now. Two writers that both hold the lock, whether two registered
delegates or two subagents that inherited one `CLAUDE_CODE_SESSION_ID`, both
pass the delivery-lock check on the same file, so nothing arbitrates a
same-time write to `spec.md`, `plan.md`, `checklist.md`, or the intent file
itself. Intent 111 adds a second, lighter layer underneath the delivery lock to
close that gap.

- **Storage.** `module Claim` lives in `scripts/lib/lock.rb`, sibling to
  `module Lock`, and never touches `Lock`'s functions. Each claim is one small
  JSON file, `.claims/<artifact>.claim`, inside the intent directory (for
  example `spec.md.claim`, `plan.md.claim`), carrying `artifact`,
  `owner_session`, `acquired_at`, and `delegate` (nil unless set). Keeping one
  file per artifact means acquiring one artifact's claim never contends on
  another, and a corrupt or stale claim on one file cannot wedge the others.
- **Scope, per-intent-per-artifact, never session-global.** A claim's on-disk
  path is always `<intent_dir>/.claims/<artifact>.claim`, so it can only ever
  affect one artifact of one intent. This is the hard guard against recreating
  the collision-90 failure mode, where an over-armed bridge froze unrelated
  sessions.
- **Exclusivity is O_EXCL at acquire, not session-equality.**
  `Claim.acquire_claim` creates the file with `File::EXCL`; the first writer
  wins (`:acquired`). Any later acquire against a FRESH existing claim returns
  `:held` and names the holder, even when the caller shares the holder's
  session id. A fresh claim is never idempotently re-granted; a genuine sole
  writer acquires once and keeps the claim alive with `Claim.heartbeat`.
- **Composition, not replacement.** A lifecycle write must hold BOTH the
  intent's delivery lock (owner or delegate, `Lock.holds?`, unchanged) AND the
  specific artifact's claim. `Claim.claim_gate_reason` is the second,
  independent gate: it is DORMANT (returns nil, allow) when no claim file
  exists for the artifact, so every existing single-owner flow and the prior
  lock/bridge suite stay green unless two writers actually contend for the
  same file. `scripts/hook-lock-gate` runs the claim gate only after the
  existing `Bridge.lock_gate_decision` already allows, refreshes the caller's
  own claim heartbeat on the allow path, and denies with the holder's session
  and the artifact name when a fresh foreign claim is found.
- **Fail open, always, as a named contract.** `Claim.fail_open?(intent_dir,
  artifact, ttl:, now:)` is the one place this behavior is defined and tested:
  true only when a claim FILE exists but is unresolvable (stale past the TTL,
  or corrupt). On a true result, the write proceeds (the claim is yielded to
  the current writer) rather than being blocked, and the condition is
  surfaced on stderr from the gate and in `plastic-lock status`. Absence of a
  claim is plain dormancy, not a fail-open condition. Intent 112, which planned
  a maintenance lock on top of this test, was abandoned: no maintenance lock
  exists, and a terminal intent directory is edited only on an explicit owner
  grant.
- **CLI and visibility.** `plastic-lock claim --artifact <name>` acquires a
  claim (exit 1 and names the holder when one is already held, even by the
  same session; takes over a stale claim automatically); `plastic-lock
  release-claim --artifact <name>` frees it. `plastic-lock status` now
  includes a `claims` array, one entry per live claim, each with its artifact,
  owner session or delegate, acquired-at time, and whether it is still fresh,
  so an orchestrator checking status before respawning a helper can see a live
  writer on an artifact and skip the respawn.
- **Scope of this pass.** The claim gate wires into `hook-lock-gate`, the
  Write/Edit/NotebookEdit lifecycle-write surface (the exact path of the 108
  collision this closes). The bash-write path is a deliberate follow-up, kept
  out to hold this change to a tight, low-risk surface. Contention is
  reject-with-surface only; queuing a second writer behind the first is a
  possible future option, not built here.
- **Hook registration single source of truth** (intent 108, D7):
  `scripts/lib/hook_registry.rb` defines every event, matcher, and hook name.
  `InstallerCore#merge_claude_hooks` translates it into settings.json,
  `hooks/hooks.json` is pinned to it by test, and doctor's
  `hooks_match_registry` check flags any drift (a missing gate, a stray
  plastic hook, a stale matcher). `merge_claude_hooks` also takes a `choice:`
  kwarg (`:plastic` or `:keep`) that gates only the `statusLine` overwrite;
  hook merging itself is unaffected by the choice. `InstallerCore#statusline_choice`
  computes that choice as a pure function of the settings file, `argv`,
  `input`, and `reinstall`: no existing line or an already-Plastic line always
  resolves to `:plastic`; otherwise it reads a `--statusline keep|plastic`
  flag, then falls back to `:keep` on `--reinstall`, an interactive prompt
  (`prompt_statusline`) on a tty, or `:keep` as the safe non-interactive
  default. Claude's five edit-path gates (code-gate, lock-gate, savepoint-pre,
  links-gate, create-gate) register as ONE PreToolUse hook, `edit-gates`
  (`hooks/edit-gates` -> `scripts/hook-edit-gates`), on the union write matcher
  (Write, Edit, NotebookEdit, and the Serena MCP edit tools; intent 244). The
  gates themselves did not go away: the dispatcher parses the PreToolUse stdin
  payload once and runs all five in-process, in the fixed order savepoint-pre,
  lock-gate, code-gate, links-gate, create-gate, with the first deny ending
  evaluation. Per-gate tool applicability, which used to be encoded by three
  separate matcher groups, now lives in `HookRegistry::GATE_TOOLS`:

  | Gate | Applies to |
  |---|---|
  | savepoint-pre | Write, Edit |
  | lock-gate | Write, Edit, NotebookEdit, Serena edit tools |
  | code-gate | Write, Edit, NotebookEdit, Serena edit tools |
  | links-gate | Write, Edit |
  | create-gate | Write, Edit, Serena edit tools |

  bash-gate stays registered separately on its own `Bash` matcher (the old
  hand-rolled merge literal had once dropped it, so it shipped dead; that gap
  is what the derived registration exists to prevent). A crash inside any one
  gate's logic is isolated (its own rescue, one stderr line, evaluation
  continues) and never denies the call by itself. Each gate's own deny shape
  is unchanged: stderr plus exit 2 for code-gate, links-gate, and create-gate;
  stdout `permissionDecision` JSON plus exit 0 for lock-gate; savepoint-pre
  never denies. Codex collapsed the same way (intent 251): its `apply_patch`
  matcher carries ONE registered command, `edit-gates`, and `scripts/codex-hook`
  parses stdin once, parses the apply_patch envelope once, and runs all five
  gates in-process through `scripts/lib/codex_edit_gates.rb`, which drives the
  SAME `scripts/lib/edit_gates.rb` functions Claude's `hook-edit-gates` drives,
  so the two harnesses cannot drift. Two Codex-specific rules live only in that
  library: create-gate applies to Add operations only (Update, Delete, and Move
  defer to the PostToolUse `gate-check` backstop), and savepoint-pre runs as its
  own first pass over every operation so its ledger line lands even when a
  later gate blocks the call. The five `scripts/hook-<gate>` CLI wrappers lose
  their last production caller but are retained on purpose as the per-gate
  isolation surface for the hook contract tests that drive them. The bash gate
  composes the code gate AND the lock gate over every write target, including
  interpreter one-liners (`ruby -e`, `python -c`, `perl -e`, `node -e`
  carrying a write verb plus a quoted absolute path); a trailing `# plastic-ok`
  comment allows a sanctioned command and logs it to
  `~/.plastic/.cache/gate-escapes.log` (the escape is scoped to code-gate
  only; lock-gate, links-gate, and create-gate still evaluate normally). The
  worktree gate confines only paths inside the project repo (derived from the
  code worktree path). Reads and searches are never gated.
- **Scope boundary**: `worktree.rb` is pure provisioning and lock-state logic. It
  never edits `projects.yml` and never mutates qmd. The PreToolUse gate that
  blocks edits outside the active worktree, and the cleanup policy that decides
  merge-vs-remove on the completion path, are layered on top by sibling intents.

## doctor: Codex hook registry vs. dispatcher agreement (intent 200)

`codex_hooks_registered_check` (`doctor.rb`) only diffs `~/.codex/hooks.json`'s content
against what `HookRegistry.codex_hooks_json` would emit; both sides come from the registry,
so a pass proves only that the registry agrees with itself. It never looks at
`scripts/codex-hook`, the actual dispatcher every Codex tool call runs through, so it cannot
see a registered gate with no real branch there, or a dispatcher branch nobody registers.
Both shipped: `links-gate` registered and reported healthy with no dispatcher branch in
v1.4.0 (intent 192), invisible to doctor and the suite until intent 198 found it by hand;
`bash-gate` fully implemented but never registered on Codex (intent 203), so a shell write
bypassed every gate while doctor again reported Codex healthy.

`codex_hooks_implemented_check` (intent 200) closes both directions: the dispatcher's
supported-gate list is read out of `scripts/codex-hook` itself by plain source-text
extraction (`codex_dispatcher_gate_names`, its `STATE_HOOKS`/`SHELL_HOOKS` constants plus its
top-level `case gate` statement's `when "..."` labels), never a hand-kept duplicate in
`doctor.rb` (a duplicate would be the exact bug this check exists to catch, one level up).
`scripts/codex-hook` itself is unmodified: it keeps failing open (`exit 0`) on an
unrecognized gate; the loud failure belongs to `doctor` alone. The extraction is
self-checking: if it finds zero gate names (a future reshape of the dispatcher the regex no
longer matches), the check fails loudly and says the dispatcher could not be read, rather
than silently reporting the healthy pass a zero-name read would otherwise produce.

**Claude closed its own version of the same hole (intent 244).** At the time intent 200
shipped, Claude registered every edit-path gate as its own launcher file, so "is it
implemented" was answered by a different, existing shape (`hooks_exist`/`hooks_executable`)
and this class of check did not apply. Intent 244 collapsed the five edit-path gates
(code-gate, lock-gate, savepoint-pre, links-gate, create-gate) into one registered hook,
`hooks/edit-gates` -> `scripts/hook-edit-gates`, which reopened exactly the same hole one
level up: a gate could ship registered in `HookRegistry::GATE_TOOLS` with no real branch in
the dispatcher's `case gate` statement (always allows, silently), or a dispatcher branch
nobody registers (dead code). `claude_hooks_implemented_check` (`doctor.rb`) is the Claude
twin of `codex_hooks_implemented_check`: it reads `scripts/hook-edit-gates` as plain text
(`claude_dispatcher_gate_names`, the file's `when "<gate>"` labels), compares that against
`HookRegistry::GATE_TOOLS.keys` in both directions, and fails loudly (rather than silently
passing) if the extraction finds no recognizable gate names at all, the same self-checking
posture as its Codex counterpart.

## installer: hook purge by registry (intent 275)

`purge_stale_plastic_hooks` decided ownership of a settings.json hook entry with
`cmd.to_s.include?("plastic-")`: any command carrying that substring anywhere was deleted
before the merge rewrote Plastic's own registrations. On 2026-08-23 the 1.11.0 update applied
this to the owner's own SessionStart hook, `~/.claude/hooks/plastic-writing-style`, registered
outside `HookRegistry` (global intent 32b). The entry vanished from settings.json with no
message, and the writing-style skill stopped loading in every session until `/plastic-doctor`
found the orphaned launcher a day later. Three sibling functions carried the identical shape:
`purge_stale_codex_hooks` (`cmd.include?("codex-hook")`), `remove_claude_hooks`, and
`remove_codex_hooks`.

Ownership is now registry membership, never a substring. `HookRegistry.claude_purge_command?`
tokenizes a settings.json command (splitting on whitespace, stripping quotes, dropping a
trailing `.rb`) and checks each token's basename against
`claude_purgeable_launcher_names` -- the union of `claude_launcher_names` (what Plastic
registers now), `CLAUDE_NON_HOOK_LAUNCHERS` (installer-placed launchers `events` does not
cover, e.g. `plastic-statusline`), and `RETIRED_CLAUDE_LAUNCHERS`. `HookRegistry.codex_purge_command?`
checks the first token's basename against `CODEX_DISPATCHER_BASENAMES` (`codex-hook`):
every Codex entry is an argument to one shared dispatcher command, so the dispatcher's own
filename, not the argument, is what identifies an entry as Plastic's.

`HookRegistry::RETIRED_HOOK_NAMES` is a hand-kept, frozen list of hook names Plastic has
registered and no longer does (`code-gate`, `create-gate`, `links-gate`, `lock-gate`,
`savepoint-pre`, `qmd-search`, `retrieval-gate`, `model-instructions`, `opus-manual`), seeded
from git history. It exists because an old install's settings.json can carry an entry for a
launcher `events` no longer mentions, and nothing else can prove that entry was ever Plastic's.
It is purge-only and stays disjoint from `claude_launcher_names`: folding retired names into
the current list would make `hooks_exist` demand launchers that no longer ship.
**Maintenance duty:** renaming or removing a hook from `events` requires adding its old name to
`RETIRED_HOOK_NAMES` in the same change, or every existing install keeps a dead registration no
update will ever clean up.

Both merges now report in both directions instead of failing silently.
`purge_stale_plastic_hooks`/`purge_stale_codex_hooks` return every entry they removed, and
`merge_claude_hooks`/`merge_codex_hooks` print a header plus one line per removal (the
`migrate_legacy_plugin` shape, silent when nothing was removed). `merge_claude_hooks`
additionally scans its post-purge output for any surviving `plastic-`-prefixed command the
registry did not recognize, and prints it under its own header naming the reserved-prefix
rule. Had that existed in 1.11.0, the update would have said "kept `plastic-writing-style`,
the prefix is reserved" instead of deleting the hook without a word.

## doctor: unowned hook entries and stray skills (intent 276)

Moving hook ownership to registry membership fixed the write side, but it narrowed the read
side without replacing it. `hooks_registered` and `hooks_match_registry` both filter
`settings.json` commands through an ownership predicate before comparing, so a command that
fails the predicate never enters either comparison and is invisible by construction. Two real
failure states fell through this gap: a `plastic-`-prefixed command the registry never
registered (a hand-edit, a squatter, or a user hook that took the reserved prefix), and a live
Plastic registration whose launcher file is gone from disk, which no-ops silently on every
event.

`hooks_entries_owned` (Claude) and `codex_hooks_entries_owned` (Codex) close this by walking
every command in the live config with no pre-filter and classifying each one into one of two
failure modes, or silence. Mode (a), an unowned `plastic-`-prefixed command, warns: it is a
naming collision in someone else's file, Plastic will not touch it, and the remedy is a
rename by its owner, mirroring the notice `merge_claude_hooks` already prints at merge time.
Mode (b), a current registration whose launcher is missing from disk, fails: it is Plastic's
own registration silently doing nothing. Mode (b) keys off `claude_current_command?`
(current registrations only, intent 277), not `claude_purge_command?` (current plus retired
plus non-hook launchers): testing against the purge predicate would fire on every install
still carrying a retired entry, since a retired launcher's file is absent from every current
install by design. That case already belongs to `hooks_match_registry`, so a retired entry is
skipped here rather than double-reported. A third-party hook carrying no `plastic-` token is
silent: it is none of Plastic's business, and warning on it would false-positive on every
user with an unrelated hook.

The skills half of the reserved prefix extends `stray_skills_check` (intent 158a) rather than
duplicating it: the manifest-diff ownership test it already runs, a `plastic-*` skill
directory the manifest does not track is a stray, was already correct. What 276 fixed is that
a missing or unreadable manifest made the check return `nil` and vanish from the report
entirely, exactly the state where stray-skill detection is needed most; it now returns `warn`
when skills are installed and ownership cannot be verified, or `pass` naming that there was
nothing to verify when none are. The message and `fix_hint` now state the reserved-prefix
rule and the rename remedy, mirroring `hooks_no_orphans`'s post-275 wording. `plastic-` is
reserved for hooks and skills alike, and `stray_skills` runs through the same shared
`check_flat_skills_and_stray` call every non-Claude agent directory (Codex, Hermes) already
uses, so the fix reaches them with no second implementation.

## living-document

This is a living document. When Plastic's architecture, lifecycle, conventions,
skills, hooks, or harnesses change, this file and `architecture.md` must be
updated in the same change.
