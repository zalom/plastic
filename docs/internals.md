# Plastic Internals

This is the deeper companion to the README's "How Plastic Works" section. The
README states the idea; this document explains the operational mechanics: how
Plastic makes work come out the same shape no matter who or what produces it,
how tight that guarantee actually is today, and what is still missing.

## deterministic-by-design

Plastic splits every unit of work into two parts.

- **The blueprint** is the deterministic part: conventions, templates, directory
  structure, lifecycle stages, the record, IDs, and linking rules. It describes *how
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
  it (script output, a frontmatter schema, directory naming, a record hook
  line, a hardcoded instruction string).
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
hook, and test, plus the record hook that writes the ledgers from filesystem state, the
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
skills (`intent-speccing`) and the curator surfaces
(the `store-curating` skill, renamed from `intent-curator` at 158a while its
agent counterpart `plastic-intent-curator` kept its name, plus (removed in 2.0, intent 304)
`future-intent-researcher`).
These produce INDEX or cluster reorganizations with no output template at all:
section set, ordering, depth, cluster naming, and orphan thresholds all drift.
`spec.md` moved out of this group at intent 163: `intent-speccing` now owns it
through a fixed eight-section template (`templates/spec.md` plus
`references/per-section-fill-rules.md`), so `spec.md` is no longer the
least-constrained artifact in the framework. Intent 299 adds `direct` to the
group, taking it to six: it is a prose router with no script and no template
behind it, deciding by judgement which of five routes a prompt takes, with
only its `references/request-signals.md` table to constrain the call.

Auto mode adds five more agent surfaces, the role files that ship in `agents/`:
`plastic-brainstorming`, `plastic-spec-specialist`, `plastic-planner`, (removed in 2.0, intent 304)
`plastic-executor`, and `plastic-enforcer`. They are thin handoff contracts (one
role per cycle stage) rather than free-prose producers: each names what it consumes
and produces, and the enforcer (which is the auto orchestrator itself) sequences and
reviews them. The installer syncs `agents/` into each harness agent directory and
tracks the role files in the manifest, so they prune on update and uninstall with the
skills and hooks. The team model lives in `skills/auto/references/agent-architecture.md`.

The mixed 18 are template- or script-backed skills with free-prose content
pockets: the lifecycle producers, the execution skills, the maintenance skills,
the `intent.md` template (fixed skeleton, free prose sections), and the two
recorded `evals.json` files (fixed schema, brain-written assertions).

## the-harness-system

Removed in 2.0 (intent 302): the edit-path gates (edit, bash, code, lock, links), the create gate, and the stage-transition gates are gone with their code. The paragraphs and list items of this section that described them were removed with them; what remains is the `record` hook (savepoint line, lock heartbeat, day ledger) and the doctor checks that replace enforcement (intent 308).

A **harness** is anything that constrains a brain step toward blueprint-conforming
form. Harnesses come in two layers, distinguished by *who needs them*.

**Layer 1: shared harnesses (human and AI).** These ARE the blueprint. A human
learns them and walks the cycles in order; they constrain everyone identically.
Three mechanisms:

- **Convention**: the rules a brain must obey (the ID algorithm, slug shape, stage
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
milestone ledger (newest at the bottom) that the `record` hook writes automatically at
each lifecycle boundary. That is the existing hook mechanism bound to the artifact-write
trigger, with the ledger as a derived form-fix on top. It is sugar over the conventions,
never a source of truth: state stays derivable from files-on-disk and the ledger is
rebuildable via `Savepoint.rebuild_savepoint`. The ledger and the stage derivation it rests on
live in `scripts/lib/savepoint.rb` (intent 303), apart from the session pointer in `bridge.rb`.
The `plastic-intent-savepoint` skill is now a thin (removed in 2.0, intent 304)
reader/verifier, not a writer.

State-from-ledger (intent 81) makes the ledger the read-once answer to "what stage, and is it
done", so a resuming agent reads `savepoint.md` first instead of probing which files exist. The
grammar gains three line classes on top of intent 34's artifact-landing milestones, all keyed by
a `(stage, milestone)` pair for idempotency (`Savepoint.savepoint_recorded_pairs`):

- a **born `What` line**, stamped by `new-intent` at creation (not left to a hook firing), so
  even a freshly parked future intent carries the first bookend deterministically;
- a **terminal `Done delivered|abandoned` line**, written by the completion path
  (`Savepoint.append_terminal_savepoint`) as the intent transfers into INDEX's Completed/Abandoned
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
closing-step slot each already uses for its QMD reindex; `plastic-intent-continuing` reads the
ledger's last line as a cheap last-event signal, purely as a read. `INDEX.md` stays the single
status writer throughout; the ledger, like the intent-dir one, is sugar, never a source of truth.

The roadmap read path (intent 148) sits on top of that ledger. `scripts/lib/roadmap_queue.rb`
(`RoadmapQueue`, constructor-DI and hermetic: clock and paths injected, no eval, no ENV or global
config seam; a thin `scripts/roadmap-next` CLI wraps it, both registered in
`InstallerCore#core_files` and covered by a hermetic test) is the one reader the auto loop and
`plastic-intent-continuing` share. It does two things: liveness-ranks the tier's `roadmaps/*.md`
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
(`--which`, for `plastic-intent-continuing`) returns `tie_candidates` so the skill's single ask
resolves the tie. The design is file-based throughout (roadmap `.md`, the 134 ledger, INDEX.md),
DB-ready but not DB-dependent: `RoadmapQueue` is the single seam a future 147 DB-backed read
swaps behind without changing either caller. A sibling seam covers ranking itself: dispatchable
candidates are value-ordered by an injected `ranker:` (default `FileOrderRanker`, today's file
order), reported as `ranking_strategy` in the payload, so intent 173's decision-systems
recommendation can replace the ordering rule without reworking parsing, frontier detection, or
the rest of the JSON contract.

A companion rule keeps the intent-dir ledger itself honest. `Savepoint.savepoint_phantom_lines`
(intent 134) is pure and disk-only, no bridge or session resolution and no writes, matching
intent 52's decoupling precedent: it flags a `savepoint.md` line that disk evidence contradicts,
in three classes: a file-landing milestone (built from the same map `savepoint_milestone` uses)
whose file is absent or still a sentinel placeholder; a duplicate `(stage, milestone)` pair (the
later occurrence is the one flagged); or a state line, `How  started` or `Exec  started`, whose
stage prerequisite (the PRECEDING stage's real artifact, not its own, since a `started` line
legitimately fires before its own stage's file is real) is absent on disk. The bug-131 bridge
clobber and the 124a out-of-band merge are the two live precedents this guards against: either
can leave a phantom or dropped line that nothing previously detected. The
`plastic-intent-savepoint` skill's verify step runs the detector and, on a hit, auto-rebuilds via (removed in 2.0, intent 304)
`Savepoint.rebuild_savepoint` for a live (INDEX Active) intent; for a terminal (Completed/Abandoned)
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
reaches `pass` once every remaining gap is excluded.

The same registration also holds on doctor's per-intent surface: `doctor.rb --intent <id>`'s
`intent_savepoint_truthful` check (intent 222) reports the same fact for one intent, so intent
281 routes its missing-`savepoint.md` branch through the same loader under the same rule id,
`savepoint_operational`, rather than minting a second rule name for one gap. That surface
honors the exclusion only when the intent is terminal in its store's `INDEX.md`, which is the
condition the store-wide sweep already applies, so a stray id can never silence the live,
repairable warning `scripts/end-intent`'s pre-write structure check raises on a still-Active intent. The
phantom-line half of that check stays non-suppressible by id or scope, per intent 211.

`RuleCatalog::REVISION_RULES` shares the
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

A registered row can go dead: the intent's gap got repaired, the id was mistyped when the row was
written, or the intent directory is gone. Left alone, the exclusion file only ever grows into an
unreviewable list. Intent 280 has `check_done_signals` diff the loaded table against the same
INDEX/directory/finding walk it already runs, via one pure predicate,
`DoctorExclusions.dead_rows(loaded, consumed:, known_ids:)`, that is handed the walk's results and
has no access to the file itself - the same self-diff trap 208 named for a different check stays
structurally impossible here. A dead row reports as one of two buckets: `:no_finding` (the id
names an intent doctor walked, but the rule fired nothing to suppress this run) or `:no_intent`
(the id names no walked directory at all - a typo, or a deleted intent; the two are
indistinguishable from the data available, and the remedy is the same either way). The count, the
buckets, and the file path fold into `savepoint_operational`'s message and `details` exactly the
way the exclusion count already does; the notice is purely informational and never moves the
check off `pass` or changes doctor's exit code - a stale governance-record row is bookkeeping
drift, not a store regression. `maintenance-run --tool register-exclusions --prune [--apply]` is
the owner-gated remedy: dry-run by default, it calls the same `dead_rows` predicate and the same
comment-preserving writer as the add direction. Two classes of row that would otherwise read as
dead are held harmless before anything is written: an id whose dir was skipped for a fresh
delivery lock (the skip would leave it out of the walk entirely), and an id whose intent has not
reached a terminal state yet (`savepoint_operational` only fires on a terminal intent, so the row
has nothing to suppress *yet*). A rule left with zero ids after pruning is dropped from the file
rather than rendered as a bare `rule_name` line, which the loader would reject. Like the add
direction, `--prune` writes no `revisions.md` entries.

Removed in 2.0 (intent 307): the `/tmp` bridge JSON and every `Bridge` method that read or wrote it; the session pointer plus `delivery.lock` replaced it, through `scripts/lib/arm.rb`. The bridge prose in this document describes the 1.x cache as it was. Session resolution feeds the record hook and the lock (intent 52; the gate hooks it once fed were removed in 2.0, intent 302). Claude Code does
not export a session id env var into the hook environment; it passes `session_id` on the hook
stdin JSON. So the bash wrappers parse `session_id` out of stdin (in Ruby, never in bash) and
hand it to the hook scripts as a second argument. `Bridge.resolve_session` then takes the
first non-empty of three sources, in precedence order: the explicit stdin `session_id`, the
`CLAUDE_CODE_SESSION_ID` environment variable, and a derived `auto-<digest>` key
(`Bridge.derive_key`, a short SHA256 of `store/intent_id`). The derived key is deterministic,
so a session-less arm and a later session-less record resolve to the same bridge file
instead of writing `plastic-.json` with a null session. `Bridge.write` now refuses an empty
session, so a null-session bridge can never be persisted.

Because that scan parses every `plastic-*.json` on each fire, the temp directory has to stay
small or the per-fire cost grows without bound (intent 67). `Bridge.purge_done_bridges` runs
on `arm_auto` and on `disarm_auto`, so every auto run cleans up dead bridges at its start and
at delivery. The rule is terminal-state, not age-based (intent 80). A bridge is purged only when
its intent is terminal: its id is no longer in its store's `INDEX.md` `## Active` block.
`Bridge.intent_active?` resolves that INDEX from the bridge's own `intent.store` (the INDEX lives
at the parent of the `store/` directory), scans only the `## Active` section, and reports whether
the bridge's `intent.id` is listed. An Active intent's bridge is kept unconditionally, because
while the intent is live the bridge is load-bearing: it is the continuation signal (a parked or
interrupted run resumes from it) and the anti-collision lock for parallel deliveries on one store.
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
`Savepoint.rebuild_savepoint` when the ledger and the filesystem disagree, and derives the next
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

`hook-capture` follows the same two-channel shape for the dashboard (intent 125): it keeps
its existing `additionalContext` cockpit dump unchanged, and now also emits a top-level
`systemMessage` one-line summary (counts, and the next big thing when there is one) from a
pure `DashboardBanner` renderer. It degrades silently on any failure (subprocess, JSON,
renderer), so a broken or slow dashboard call never crashes `UserPromptSubmit`.

## what-exists-today-vs-what-is-missing

Removed in 2.0 (intent 302): the edit-path gates (edit, bash, code, lock, links), the create gate, and the stage-transition gates are gone with their code. The paragraphs and list items of this section that described them were removed with them; what remains is the `record` hook (savepoint line, lock heartbeat, day ledger) and the doctor checks that replace enforcement (intent 308).

Plastic ships **23** harness entries today. By strength on the form-determinism
axis (hard-block beats soft-steer beats advisory):

| Strength | Count | Examples |
|----------|-------|----------|
| hard-block | 7 | the lifecycle gate, the code gate, the ID and hash scripts, the dashboard renderer, config resolution |
| soft-steer | 10 | the prompt hooks, the savepoint hook, the intent/checklist/plan/savepoint/index templates |
| advisory | 6 | session-start and statusline hooks, the PLASTIC.md conventions (the active-intent-gate fragment was removed in 2.0, intent 304), both `evals.json` files |

Two honest caveats about the existing harnesses:

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

The power-tools `UserPromptSubmit` hook was removed in 2.0 (intent 309): `PLASTIC.md`
carries the "prefer QMD, prefer Enola or Serena" recommendation once per session (intent
305), so a per-prompt reminder only repeated it. `scripts/lib/power_tools.rb` stays: doctor's
Serena and Enola readiness checks use its presence probes (`PowerTools.qmd?`,
`PowerTools.serena?`, `PowerTools.enola?`, PATH and marker-file walks with no subprocess).
The name `power-tools` is in `HookRegistry::RETIRED_HOOK_NAMES`, so an old settings.json or
`~/.codex/hooks.json` entry is purged on the next install or update. History: until intent
246 this hook also injected scored `qmd search` hits; intent 225 measured that injection at
0.24 intent-level recall@3 against a plain ripgrep control at 0.18, while agent-driven
`qmd query` scored 0.71, so the injection went first and the reminder last.
`QmdSync.search` is untouched and still backs the read-only `scripts/qmd-sync search` verb.

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
  present with no unknown sections. The same consumers (the CLI, `end-intent`, doctor)
  share this one definition (the create gate that once shared it was removed in 2.0, intent 302). See the sanctioned-creation-path
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

Removed in 2.0 (intent 302): the edit-path gates (edit, bash, code, lock, links), the create gate, and the stage-transition gates are gone with their code. The paragraphs and list items of this section that described them were removed with them; what remains is the `record` hook (savepoint line, lock heartbeat, day ledger) and the doctor checks that replace enforcement (intent 308).

Intent 60 enforced the born-complete OUTCOME but not the PROCESS: an agent could
bypass `plastic-intent-creating` and hand-author intent files with the same Write
primitive the skill uses. Process-purity is unprovable (the skill and a
hand-author look identical at the tool layer), so the achievable targets are the
INVARIANT (every intent file is born complete and structurally sanctioned) plus
the ERGONOMICS (the sanctioned path is the cheapest action an agent can take).
Four coordinated pieces deliver that.

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

Removed in 2.0 (intent 302): the edit-path gates (edit, bash, code, lock, links), the create gate, and the stage-transition gates are gone with their code. The paragraphs and list items of this section that described them were removed with them; what remains is the `record` hook (savepoint line, lock heartbeat, day ledger) and the doctor checks that replace enforcement (intent 308).

`AGENTS.md` states the classification rule: a step becomes a script only when its output is
a pure function of already-committed artifacts (spec.md, plan.md, checklist.md, outcome.md,
test results, the diff). Everything else stays judgment and stays with the agent. Four
scripts, each a thin CLI over its own `scripts/lib/` module, apply that rule to the four
lifecycle steps that qualify.

`scripts/start-intent` composes `Bridge.arm_auto` or `Bridge.arm_guided`, then reads the four (removed in 2.0, intent 304)
lifecycle files and prints a resume-station report. It never releases or takes over a lock.

`scripts/scaffold-intent` is one CLI with one verb, `backfill` (its `spec`, `checklist`, and
`outcome` subcommands were removed in 2.0, intent 308). It runs `BackfillIntent`
(`scripts/lib/backfill_intent.rb`), the writer `scripts/end-intent` runs at every close: each
of spec.md, plan.md, `actions/ACTION_1.md`, and outcome.md that is missing or still the
placeholder is written from the record (the intent file, the checklist, the diff on the
intent's own worktree), every judgment section keeps the template's stub, and a file with
hand-written content is never touched. `end-intent` then runs doctor's per-intent structure
check as a self-check that reports and proceeds; the exit-6 refusal is gone.

`scripts/verify-intent` folds doctor scoped to the intent, the added-line em-dash diff guard
(the first standing implementation of that check), a diffstat, and an optional
caller-supplied suite command into one verdict. It does not invent a project test-command
config. The doctor scan includes the `intent_ticks_lag` warning (intent 329): a WARN when the
savepoint's `Commit` ledger has entries and no checklist item is ticked.

`scripts/lib/spec_header.rb` is the only parser of the `Tier:` and `Settled:` lines at the (removed in 2.0, intent 304)
top of spec.md. `Savepoint.savepoint_tier` delegates to it. (removed in 2.0, intent 304)

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
  the `plastic-doctor` skill (resolve slug, run the verb, then the
  separate optional `qmd-sync register --store` step); and doctor's read-only
  `project_store_dir` check (warns and is fixable via the verb).
- **Scope boundary**: the provisioner is pure filesystem. It never mutates qmd,
  never edits `projects.yml`, and registration with qmd stays a separate skill
  step that no-ops when qmd is absent.

## per-agent model resolution and installer application (intent 116)

Every subagent in `agents/*.md` pins an explicit Claude Code model alias (`opus`,
`sonnet`, or `haiku`) in its own frontmatter, tiered by role: `plastic-enforcer`,
`plastic-brainstorming`, and `plastic-planner` are `opus`; `plastic-spec-specialist`, (removed in 2.0, intent 304)
`plastic-executor`, `plastic-intent-curator`, `plastic-future-intent-researcher`, and (removed in 2.0, intent 304)
`plastic-intent-discovery` are `sonnet`. None is ever `inherit` and none is ever (removed in 2.0, intent 304)
Fable by default. Fable is named in three places, and only three: the auto-mode advisory
notice below (about the human's main session, never a dispatched subagent), an
explicit `agents.models.<name>` config override, which is honored as written for a
dispatched subagent when one is configured (e.g. `plastic-brainstorming: fable`, (removed in 2.0, intent 304)
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
  `plastic-intent-discovery` dispatch inside `plastic-intent-continuing`, and the (removed in 2.0, intent 304)
  `plastic-intent-continuing` stale-future-intent triage's dispatch of
  `plastic-future-intent-researcher` (which does not itself spawn further (removed in 2.0, intent 304)
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
- **What-stage discovery agent**: `plastic-intent-discovery` (paired with the (removed in 2.0, intent 304)
  `skills/intent-discovering/SKILL.md` (removed in 2.0, intent 304) workflow) closes the What-stage gap in the
  one-agent-per-stage table. It fires inside `plastic-intent-continuing`, right after
  an intent is activated (moved from `## Future` to `## Active`) and the bridge is
  armed, running under that lock as the owner session (it does not acquire the
  lock itself and is not blocked by it): it reads the intent's `chain`/`sources`
  frontmatter, runs QMD-first
  discovery across completed predecessor work and related parked or future intents,
  and deposits its findings to `resources/discovery--<slug>.md` in the intent
  directory ONLY. It never writes the intent file, `spec.md`, or any other lifecycle
  deliverable, so the lock-owner-only write rule stays intact; the Why-stage
  `plastic-brainstorming` agent is the one that reads the deposit and enriches (removed in 2.0, intent 304)
  `## Context`.

## worktree provisioning and the delivery lock (intent 73c)

Removed in 2.0 (intent 302): the edit-path gates (edit, bash, code, lock, links), the create gate, and the stage-transition gates are gone with their code. The paragraphs and list items of this section that described them were removed with them; what remains is the `record` hook (savepoint line, lock heartbeat, day ledger) and the doctor checks that replace enforcement (intent 308).

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

- **Three distinct evidence layers and bounded delegate history** (intent 108a):
  the controller record proves whole-intent authority; a registered delegate record
  authorizes one child session under that controller; a claim record identifies
  one current writer for one artifact among already-authorized sessions. Delegate
  activity status (`active`, `finished`, or `failed`) is observational and does not
  remove the session from the string-array authorization list. A delegate remains
  authorized until a separate removal mechanism exists. Finished and failed activity
  history is capped at the 20 most recent terminal entries.

## per-artifact claim tokens (intent 111)

Removed in 2.0 (intent 302): the edit-path gates (edit, bash, code, lock, links), the create gate, and the stage-transition gates are gone with their code. The paragraphs and list items of this section that described them were removed with them; what remains is the `record` hook (savepoint line, lock heartbeat, day ledger) and the doctor checks that replace enforcement (intent 308).

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

  | Gate | Applies to |
  |---|---|
  | savepoint-pre | Write, Edit |
  | lock-gate | Write, Edit, NotebookEdit, Serena edit tools |
  | code-gate | Write, Edit, NotebookEdit, Serena edit tools |
  | links-gate | Write, Edit |
  | create-gate | Write, Edit, Serena edit tools |

## doctor: Codex hook registry vs. dispatcher agreement (intent 200)

Removed in 2.0 (intent 302): the edit-path gates (edit, bash, code, lock, links), the create gate, and the stage-transition gates are gone with their code. The paragraphs and list items of this section that described them were removed with them; what remains is the `record` hook (savepoint line, lock heartbeat, day ledger) and the doctor checks that replace enforcement (intent 308).

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

Intent 278 extended the same reporting to the two remove paths.
`remove_claude_hooks` and `remove_codex_hooks` collect the entries they delete the same
way the purges do and print them through `report_removed_hook_entries`, which took a
`qualifier:` argument so an uninstall reads "Removed 3 Plastic hook entries" instead of
the merge's "stale" wording. The statusline swap-back, which is a restored value rather
than a deleted entry, reports on its own line. No Plastic edit to a user's hook
configuration is silent now, on either harness, on either path.

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

## the day ledger and append-ledger (intent 297)

The session intent day ledger is one shared ledger per calendar day per person, in the
global store, project agnostic, with every line tagged by the session and project that
wrote it. `scripts/lib/session_ledger.rb` is the pure library behind it: every method takes
its paths as arguments and reads no environment variable. `scripts/new-intent --tmp` and
`scripts/append-ledger` are its two CLIs, and only they read the environment.

**The line formats**, byte exact:

```
- [~] [b7137962] [plastic] Change how titles appear on the resume page
- [ ] [b7137962] [plastic] Change how titles appear on the resume page
- [x] [b7137962] [plastic] Change how titles appear on the resume page
2026-08-29T13:26:52Z  Item  [b7137962] [plastic] Change how titles appear on the resume page
```

The first three are `checklist.md` lines: pending, open, and done, in that order. The state
marker is fixed width across all three states (`~`, a space, or `x`, always inside `[ ]`),
which is what makes a promote or a tick a one-byte write at a known offset rather than a
whole-file rewrite. The fourth is a `savepoint.md` line: two-space separators so
`split(/\s{2,}/)` yields three parts, exactly as every other savepoint line in the store
does, with the event column one of `Item` (promoted), `Done` (ticked), or `Note` (free
text). The day id in a directory name is local wall clock; every instant inside a line stays
UTC, an intentional asymmetry.

**The lock protocol.** The lock is on the target file itself, `checklist.md` or
`savepoint.md`, never a sibling lock file, and never an inode replaced by a rename, because a
rename swaps the inode out from under a holder. An append opens
`File::WRONLY | File::APPEND | File::CREAT` at mode `0644`, takes a blocking
`flock(File::LOCK_EX)`, writes one full line, then unlocks. The first append checks for size
zero after taking the lock, which is what lets exactly one racer write the header even though
`O_CREAT` without `O_EXCL` hands every racer the same inode. A promote or a tick opens
`File::RDWR`, takes `LOCK_EX`, scans by byte offset to find the target line, `pwrite`s its one
byte, flushes, and unlocks, all inside that single hold: identifying the target line and
flipping it are never two separate locked steps, since a caller (`append-ledger`'s
`--savepoint`) needs to know exactly which line it flipped, and a separately-locked lookup
before the flip can go stale under concurrency. `SessionLedger.set_state` returns the flipped
line's own summary (or `nil` when nothing matched) for exactly this reason. There is no
timeout and no polling: a hold covers exactly one write, and the kernel releases
an flock automatically when its holder dies, so an orphan hold cannot exist. On a filesystem
without flock support, an append proceeds unlocked, since a single `O_APPEND` write still
lands whole there; an in-place edit refuses with exit 3 rather than risk a torn
read-modify-write. This is deliberately not `Lock.with_write_guard`'s polling exclusive
pattern, which exists for multi-second read-modify-write holds a ledger append never has.

**The scaffold.** `SessionLedger.open_day` is the single scaffold implementation. Create
versus join is decided by opening `<day>.md` with `File::CREAT | File::EXCL`: the winner
renders `templates/session-intent.md` and reports `created`, every loser reports `joined`,
and a crash mid-scaffold with no md file yet is repaired by the same path on its next call. If
the render itself fails partway (a missing or relocated templates dir), the file just created
is unlinked before the error re-raises, so no zero-byte file is left behind to wedge every
later call onto the "already exists" branch with nothing to repair. `created:` in the
rendered frontmatter comes from `now` (when the scaffold call actually ran), not from `day`
(the calendar day the ledger is for): the two differ exactly when a repair or a
midnight-crossing capture scaffolds a past day's file today. Both callers use it: `new-intent
--tmp` is its CLI, and `append-ledger` calls it on every invocation, not only when the day
directory looks missing, since a directory that exists without its `<day>.md` (a crashed
scaffold, or a failed render) would otherwise never be repaired. The rendered file passes
`IntentValidator.validate` in full, which is possible because that validator reads only the
intent's own markdown file and its five sanctioned sections. `## Links` carries
`LinksProjection::EMPTY_COMMENT` verbatim, so no cross-store map build ever runs at session
start.

**The consumer list.** Who builds on this contract, and what each one needs:

- intent 298: the session-start and post-tool hooks, the per-session pointer and heartbeat
  under `.tmp/<session>/`, and capture and record.
- intent 300 (delivered): `scripts/session-commit`, which appends one `Item` or `Note`
  savepoint line per commit. See "the session branch model and session-commit" below.
- intent 301: close, `file-session-intent`, `promote-session-item`, and the carry-forward of
  open items, which is why `append-ledger item` exists alongside `pending`.
- intent 311 (delivered): `write-handoff` (the per-session hand-off in the day directory,
  written at every tick, at PreCompact through `hook-savepoint`, and at close) and
  `day-summary` (the bounded block the session-start hook injects after the joined line).
  Both are renderers over the same two files, regenerated in full on every write.

A recorded hazard, so intent 301 does not discover it mid-Exec: `LinksProjection` resolves a
ref by scanning store-root children, so a later intent whose `sources` names a day id raises
`UnresolvedRef`, its `## Links` goes unwritten, and doctor's links check may flag it. The fix
is either a resolver that knows `.sessions/` or a frontmatter-only link that projection
skips, and it belongs to intent 301, not here.

## the session branch model and session-commit (intent 300)

`scripts/session-commit --cwd <dir> --summary <text>` is how a verified checklist item
becomes exactly one git commit. `scripts/lib/session_git.rb` is the pure library behind it:
every git call goes through an injected `runner:` (`Worktree::ShellRunner` by default, the
same seam `Worktree` itself uses), every `gh` call goes through a separate injected
`gh_runner:` (`SessionGit::GhRunner` by default, since `gh` is not `git` and needs its own
seam), and the library reads no environment variable anywhere; only the CLI reads the
environment and passes what it read in as arguments.

**Repo resolution and the guards shared by both modes.** The repo root is
`git -C <cwd> rev-parse --show-toplevel`; none means the outcome `no repo`. Three checks then
run before the mode is even read, so `mode: direct` and `mode: pull_request` share exactly one
implementation of each (an independent review found these living only inside the direct-mode
path, so `pull_request` could switch a checkout holding another agent's uncommitted work, or
commit on a detached HEAD): the branch HEAD points to is read with
`git symbolic-ref --quiet --short HEAD`, which -- unlike `git rev-parse --abbrev-ref HEAD` --
succeeds on an UNBORN branch (a fresh `git init`, zero commits) as well as a normal one, and
fails only when HEAD is genuinely detached (reported as the literal string `HEAD`); a detached
`H` commits nothing; a `H` an agent owns -- its name starts with `plastic/` (every Plastic
intent worktree's branch), or `cwd` itself is a worktree checked out under
`.claude/worktrees/` -- is left completely untouched; and a repository with zero commits yet
(`git rev-parse --verify --quiet HEAD` fails) reports "no commits yet" rather than attempting a
base-branch dance that cannot resolve.

**Flow resolution.** The project slug is the longest `projects.yml` path match (the same idiom
`SessionLedger.project_slug` already uses for the day ledger). The flow is read from
`~/.plastic/projects/<slug>/project.yml`'s `flow:` block when the project and the key both
exist, else every knob defaults: `mode: direct`, `base:` from
`ScaffoldIntent.detect_base_branch` (origin/HEAD, then `main`, then `master`),
`branch_template: "session/{{day}}"`, `ticket_source: intent_id`, `workspace: checkout`. An
unknown `mode` or `workspace` value falls back to its default and always turns the whole
outcome into a `Note`, even when the git operation underneath it succeeds: an unrecognized
flow value is itself a degradation from the configured intent, and `SessionGit.commit!` folds
both facts into the one savepoint line a caller gets to write. `workspace: worktree` gets the
same treatment even though it IS a recognized value: see below.

**Direct mode, the branch rule.** Let `S` be the rendered session branch and `B` the base. A
clean tree is `nothing to commit`; an empty summary (blank after truncation) commits nothing
either, rather than reach git at all and surface as a misleading commit-msg-hook rejection. The
configured `base` must actually exist (`branch_exists?`) or the outcome is a Note naming it --
a silently-missing base used to fall through to whatever branch happened to be checked out. A
`branch_template` that references `{{ticket}}` or `{{slug}}` is rejected before rendering:
direct mode never populates those tokens, so such a template would render an incomplete ref
(`quick/` for `quick/{{ticket}}`). The rendered `S` is validated with
`git check-ref-format --branch` as a second, general safety net. Only past all of that: when
`H` is `B` or `S`, `S` is created from `B`'s tip if it does not exist yet (reused, never
recreated, when it already does) and the checkout moves to `S` -- and BOTH of those git calls
have their exit status checked (an independent review found them ignored: a conflicting dirty
file, or `S` already checked out in a sibling worktree, made `git branch`/`git checkout` fail
silently, after which staging and committing ran anyway in whatever branch was actually
checked out, landing the item straight on `B` while the Note claimed `S`). A failure at either
step is a Note naming the real git failure, and nothing is staged or committed. Only once the
checkout is confirmed to have landed on `S` (`current_branch` is re-read, not assumed) does the
dirty tree get staged and committed there, and `B` is fast-forwarded to `S`'s new tip via
`git push . S:B` -- a local push that only ever succeeds when it is a genuine fast-forward. A
`H` that is neither `B` nor `S` (a `feature/x` the owner happened to be on) still gets
committed, on `H`, with the deviation named in the `Note`. A push refused because `B` moved
ahead independently (not a fast-forward) leaves the new commit sitting on `S` and reports the
refusal as a `Note`; the commit is not lost, only not yet integrated.

**workspace: worktree is not implemented in this release.** Spec D8 originally shipped a
`git stash push`/`pop` relocation into a dedicated worktree at
`.claude/worktrees/session-<day>`, so `cwd`'s own checkout never had to switch onto `S`. An
independent review found it unsafe as written: a failed `git worktree add`, a stash pop that
conflicts with independent changes on `B`, or a rejecting commit-msg hook each left the
mechanism permanently wedged for the rest of the day (every later item failed the same way,
self-heal absent), and the commit-msg-hook case silently moved the owner's uncommitted file out
of their own working tree into the hidden worktree with no notice in the Note. The mechanism is
removed rather than hardened. `workspace: worktree` stays a valid, accepted config value (the
validator does not reject it), but `SessionGit.load_flow` now treats it as `checkout` and adds
`SessionGit::WORKSPACE_WORKTREE_NOTE` to the notes it returns, which folds into a `Note`
savepoint line the same way an unknown flow value does. The item still commits, through the
checkout, exactly as `workspace: checkout` would; only the ledger line differs, recording that
the configured workspace was not honored. A real worktree-based session workspace, if wanted, is
a follow-up intent.

**Pull request mode.** Shares the repo-existence, detached-HEAD, agent-lock, and unborn-repo
guards above, plus the empty-summary and missing/nonexistent-base checks direct mode has. The
branch name renders `branch_template` with three tokens: `{{day}}`, `{{ticket}}`, and
`{{slug}}` (the summary's first five words, kebab-cased), validated with
`git check-ref-format --branch` the same way direct mode's session branch is. `{{ticket}}` is
the intent id named by the session's pointer file (`.tmp/<session>/current`) when
`ticket_source` is `intent_id`; per intent 298's spec D6 that pointer holds exactly one line,
either today's day id or an intent id, so a day id found there resolves to the day id anyway
(the two are the same value in that case) and any other non-blank content is treated as the
intent id. The branch is cut from `B`'s tip and checked out, both with their exit status
checked the same way direct mode's are; `gh pr create --base B --head <branch> --fill` runs,
inside the resolved repository (`gh_runner.available?(repo)` and `gh_runner.run(..., dir:
repo)`), when `gh` is on PATH. Without an explicit working directory, `gh` resolves its target
repository from the calling process's own `Dir.pwd`, not `--cwd`'s repo, which an independent
review found to be the one place this library could otherwise act on a repository other than
the one it was asked about -- the normal case for a hook firing from the session's own cwd, not
the repo the item is in. When `gh` is missing, the Note names the branch and short sha the
commit actually landed on, since dropping them left the owner with no way to find the commit
from the ledger line alone. The session branch is never touched in this mode. Whether `gh`
succeeds, fails, or is missing, the checkout returns to whatever branch was checked out before
the call.

**Commit message.** The message is the summary's first line only, truncated to 72
characters, no trailer; a blank result (after truncation) commits nothing at all rather than
attempt a git commit with an empty message, which git itself would refuse and this library
would otherwise misreport as a rejecting commit-msg hook. The repository's own `commit-msg`
hook runs exactly as it would for the owner, and a hook rejection degrades to a `Note`
carrying the hook's diagnosis: its stderr, or its stdout when stderr is empty, since git and a
hook script can write their explanation to either stream and an empty diagnosis serves no one.

**Item versus Note.** Every outcome writes exactly one savepoint line. Only the two full
happy paths -- a direct commit that lands on the session branch AND successfully
fast-forwards (or merges) the base, and a pull-request commit that successfully opens its PR
-- are `Item`, with the summary format `<commit subject> (<short sha>)`. Every other outcome,
including ones where a commit did land (a wrong-branch commit, a refused push, a missing
`gh`), is a `Note`: whether the branch model reached its fully-integrated end state decides
the event, not merely whether a commit object exists.

**The CLI's own fail-open guarantee.** `SessionGit.commit!` is fail-open by construction, but
`scripts/session-commit` also wraps `SessionLedger.open_day` and the savepoint append in their
own rescues, and `main` carries a top-level one: a store or ledger failure (a read-only store
directory, an installed layout missing `templates/`) used to sit outside every rescue, so the
CLI could exit 1 with a raw Ruby backtrace on stderr and zero savepoint lines, even after the
git commit itself had already landed -- breaking the exit-0-always contract for a caller like
intent 298's `record` hook, which never expects a git-commit tool to crash the calling process.
The savepoint append also no longer depends on `open_day` having run: it calls
`FileUtils.mkdir_p` on the day directory itself first, so a damaged install that cannot open
the day ledger can still write its one savepoint line.

## compaction thresholds and the compact-instructions block (intent 312)

Two config keys and one installed block tell a session when to compact and what to do
about it. Nothing in Plastic reads the keys at runtime: the harness reports how much of
the window is used, and the model acts on the installed block. The keys exist so a user
can retune the numbers that block states.

```yaml
context_offer_tokens: 350000    # offer a compaction
context_insist_tokens: 500000   # insist on one
```

They are absolute token counts, not percentages, and they resolve through the ordinary
`scripts/read-config` path (project, then global, then the `DEFAULTS` in that script).
Intent 296's D38 settled the numbers from `research--context-thresholds.md`: models are
reliable only to roughly 50 to 65 percent of advertised context, and the mechanisms
behind that are architectural, so a percentage that is right at a 200k window would let
five times as many raw tokens pile up before firing at 1M. The three places the numbers
live (the `DEFAULTS` hash, `templates/config.yml`, and `InstallerCore#bootstrap`'s seeded
config) are pinned equal by `test/compact_instructions_test.rb`.

The block itself is `CompactInstructions::BODY` in `scripts/lib/compact_instructions.rb`,
installed into `~/.claude/CLAUDE.md` as a marked section:

```
<!-- BEGIN PLASTIC COMPACT hash:<12 hex> -->
...the block...
<!-- END PLASTIC COMPACT -->
```

`InstallerCore#inject_marked_section` is the same three-state merge (create, append,
replace) that puts Plastic's standing conventions into `~/.codex/AGENTS.md`, with the
markers as parameters. The Claude block gets its own pair rather than reusing
`PLASTIC INTEGRATION`, because the two managed files can be the same file: a user who
symlinks `~/.claude/CLAUDE.md` at `~/.codex/AGENTS.md` would otherwise have one body
silently replace the other, and an uninstall of either would strip both. Both inject and
strip resolve a symlink to its target before writing, so the atomic rename lands on the
target and a dotfiles-managed file stays a symlink.

`~/.claude/CLAUDE.md` is a partial-ownership user file, so it is never manifest-tracked.
It is stripped surgically on uninstall (`strip_claude_compact_section`), which preserves
everything the user wrote and deletes the file only when Plastic created it and nothing
else remains. `Rollback#prepare_switch` strips it too before a downgrade hands off to an
older package: no older installer knows the section exists, so nothing there would ever
replace or remove it. The Codex `AGENTS.md` section needs no such treatment, because
every older package knows that one and rewrites it on the downgrade install.

The doctor check `claude_compact_instructions` (in `check_claude_registration`) reports
the block present, well formed, and current, comparing the `hash:` in the BEGIN marker
against `CompactInstructions.body_hash` so a block an older version left behind is
reported rather than trusted. The Codex `codex_agents_md` check stops at well formed;
that difference is deliberate, not an oversight. `doctor_core.rb` keeps its own copy of
the two marker literals, as it does for Codex, but the body and its hash come from the
shared lib, so the text has exactly one home.


## living-document

This is a living document. When Plastic's architecture, lifecycle, conventions,
skills, hooks, or harnesses change, this file and `architecture.md` must be
updated in the same change.

## the session close path and the next-day sweep (intent 301)

Three pieces close the loop the day ledger (intent 297) and the capture and record hooks
(intent 298) opened.

- `hooks/close` and `scripts/hook-close` run at `SessionEnd` on both harnesses (Codex since
  intent 309, through `scripts/codex-hook`'s detached hand-off). The script reads `session_id`, `cwd`, and `reason` from the hook's stdin JSON and
  takes the Plastic home from argv. It is a no-op for the reasons `clear` and `resume`, which do
  not end a session. Otherwise it flips this session's pending `[~]` lines to dropped `[-]`,
  writes one `Note` when it dropped any, removes `.tmp/<session-id>/`, and, when the session's
  pointer names a day before today, spawns `file-session-intent` detached so a slow filing never
  blocks the harness shutdown. `scripts/lib/session_close.rb` holds the logic with an injected
  spawner; the script always exits 0.
- `scripts/file-session-intent --day <YYYYMMDD> [--carry-to <YYYYMMDD>]` files a day: pending
  lines become dropped, open lines are carried into the target day once (deduplicated against
  the target before the append, flipped to moved `[>]` after it, so a rerun after a crash never
  duplicates), the four documents `spec.md`, `plan.md`, `actions/ACTION_1.md`, and `outcome.md`
  are regenerated from the ledger alone (`scripts/lib/session_backfill.rb`), and the day file
  gains a `closed:` timestamp. A day whose checklist is newer than its `closed:` stamp is filed
  again. Prints `filed <day>` or `skipped <day>: closed`; a filing error goes to stderr and the
  next boot tries again.
- `scripts/promote-session-item --day <YYYYMMDD> --match <substring>` turns the newest open
  (else pending) matching line into a registered intent through `scripts/new-intent`, records the
  origin as `session_day:` frontmatter plus a line under `## Context`, registers it under
  `## Future` in the store's INDEX, flips the line to promoted `[^]`, and writes a `Note`. No graph
  edge points at the day id: the day ledger is not a store node.
- The first-boot sweep in `scripts/hook-session-start` runs before today's ledger is joined: every
  `.sessions/<day>` directory with a real date before today that is not closed (or was reopened
  by later lines) is filed with `--carry-to <today>`, oldest first, at most three per boot within
  a five-second budget; the context line names how many were filed and how many wait.

`SessionLedger::STATES` gained `moved: ">"`, `dropped: "-"`, and `promoted: "^"`; `set_state`
accepts `session: nil` for any-session addressing; `flip_all` flips every matching line under one
lock with one `pwrite` per line.

The skill-authoring guides live under `docs/skill-authoring/` since 2.0 (intent 304); they are reference material, not installed skills.

## the context budget bench (intent 313)

Intent 296 ruled two numbers for how much doctrine a session reads at boot: the core block
under 8,192 bytes, and the whole per-boot read under 15,000. Until intent 313 both were
estimates in a design document, and the only enforcement on disk measured two static files
without ever running the thing that injects context. `bin/plastic-bench` measures it instead.

```
bin/plastic-bench                      # 5 boots against a fixed fixture, the default
bin/plastic-bench --repeat 20          # more samples
bin/plastic-bench --core-file PATH     # measure PATH as the core block (proves a ceiling can fail)
bin/plastic-bench --repo PATH          # measure another Plastic checkout
```

It exits 0 when every ceiling holds, 1 when one is crossed, and 2 on bad usage.
`test/context_budget_bench_test.rb` runs the same module inside the suite with three repeats,
so a crossed ceiling is a red suite, not a report nobody ran.

**How the fixture is built.** A `Dir.mktmpdir` home, a real `scripts/install.rb --claude` into
it, then a fixed store on top: one active and two future global intents, one active and one
future project intent, the future ones created exactly 30 days before today so the rendered
stale line never drifts with the calendar. The install is what makes the measurement faithful:
without `~/.claude`, `Doctor#check_agent_registration` fails, the rest of the core checks
short-circuit, and the boot banner reads `error` instead of the `success` a real session sees.

The child process gets `HOME`, `PLASTIC_HOME` and `PLASTIC_TMP` inside the fixture, a fixed
session id, no `RUBYOPT`, and a `PATH` of exactly one entry: the running interpreter's
directory. That last one is load-bearing twice. `hook-session-start` shells out to
`scripts/read-config` three times and `read-config`'s shebang is `#!/usr/bin/env ruby`, so any
`PATH` carrying `/usr/bin` would run those reads under the system Ruby while the report named a
different interpreter; and with nothing else on `PATH`, `qmd` is unfindable on every host, so
the optional QMD status line can never move the byte count between machines.

**What it measures, and what is enforced.**

| Row | What it is | Ceiling |
|---|---|---|
| core block | `PLASTIC.md` bytes | **under 8,192**, intent 296's ruling |
| boot injection | the `additionalContext` `hook-session-start` emits for the fixture | **under 15,000**, intent 296's whole-read ruling |
| skill catalog | every `skills/*/SKILL.md` frontmatter `name` + `description` value the harness loads | reported |
| boot injection + skill catalog | the two above | **under 17,500**, a 313 ratchet, lower it, never raise it |
| median skill body | the median `SKILL.md` body, frontmatter excluded | reported |
| doctrine working set | boot injection + `skills/_decision-tables.md` + the median skill body | reported against the 15,000 target, with its gap |

Bytes are the budget; two token estimates ride along, a word-based one (`words * 1.3`, the same
arithmetic as `scripts/lib/skill_lint.rb`, so the bench and the linter can never disagree) and
`bytes / 4`. Neither is a tokenizer. Rows that are arithmetic over other rows print `-` for the
word estimate rather than a number that looks measured and is not.

**Why the working set is reported and not enforced.** The cut inventory's own composition for
the 15,000 (core + fragments + a median skill body) sums to 17,621 in its own after-column, and
its "median skill in play" row is a per-skill *directory* measure, not one file. The working set
therefore stands above the ruled target today, and the gap is the skill bodies: three skills sit
over 15 KB and pull the median up. Enforcing 15,000 there would turn the suite red for work no
intent owns, and enforcing a ratchet would turn it red on a median that steps by about a
kilobyte whenever a skill is added or removed. So the bench prints the number and the gap on
every run, and the ceiling stays on the boot injection, the one quantity that is read on every
boot and can be measured exactly.

The bench is a maintainer tool. It lives under `bin/` beside `bin/test`, is deliberately absent
from `installer_core.rb`'s manifest, and is never installed into `~/.plastic`: it reads this
repository's own files and a fixture it builds, so it has no meaning on an installed copy.

## the ScreenPaint registry, and late-capable engagement (intent 331a)

Before 331a, `scripts/lib/screen_paint.rb` recognized a screen's opening line against one
hard-coded `OPENER_RE`, and `MessageDisplay` (the `hooks/message-display` adapter) let only
chunk 0 decide whether a message was a screen at all — a prose-first or fenced reply left that
decision final, wrong, and unpainted for the rest of the message.

**The registry.** `ScreenPaint.register(kind, opener:, paint: nil)` adds one entry (a Regexp or
a callable) to a module-level registry; `ScreenPaint.kinds` lists every registered name, and
`classify`/`paint` consult the registry instead of a single constant to decide whether a line
opens a screen. `paint:` is optional and defaults to the shared pipeline everything else in the
file already implements — no shipped kind carries its own palette; the registry's only job is
that a new kind's opener is recognized without editing this file, and that a kind CAN supply its
own paint lambda on the rare day one needs one. The five shipped kinds (`intent`, `state`,
`roster`, `delivered`, `delay`) register at the bottom of `screen_paint.rb` itself, decomposed
from the original `OPENER_RE` into its `"## "`-prefixed half and its bare-glyph half, so the
set of lines recognized as an opener is unchanged. A caller-added kind lives in its own file,
`scripts/lib/screens/<kind>.rb`, calling `ScreenPaint.register` on load; `scripts/report-screen`
glob-requires `lib/screens/*.rb` (sorted, tolerating an absent or empty directory), and
`installer_core.rb`'s glob-derived `screen_files` (mirroring `template_files`/`hook_files`)
ships that file to an installed `~/.plastic` — "add a file, not a diff" is otherwise false for
an installed copy, not just an in-repo one.

**Late-capable engagement.** `MessageDisplay#handle_chunk_zero` and `#handle_later_chunk` both
scan their own chunk's delta, line by line, for the first line that opens a screen
(`split_at_opener`) — not only at chunk 0, and not only at the very start of a delta. A chunk
that engages (the FIRST one whose own text carries an opener, whatever its index) writes the
shared `SCREEN` decision file with ITS OWN INDEX as a decimal integer (replacing any `NOSCREEN`,
which is no longer a final answer once a later chunk engages), returns the text before the
opener as `displayContent`, and buffers the opener onward at its own index. The final chunk —
routinely a separate process — reads that index back off `SCREEN` and waits, and later splices,
only from there, rather than burning its whole poll budget on chunks before the engaging one
that were never buffered at all (they already reached the terminal, unmodified, through the
ordinary passthrough path). A lone fence line immediately wrapping the opener — one right before
it in the engaging chunk's own prefix, one right after the painted region in `finalize` — is
dropped; a fence in an earlier, already-displayed chunk is never touched, and an unrelated code
block elsewhere in the message survives verbatim. `hooks/message-display` mirrors this at the
shell layer: a chunk is handed off to Ruby, whatever its index — chunk 0 included, not only a
later one — when its own delta value contains a bare `▶` or `✔` anywhere, raw or `\u`-escaped —
every shipped opener contains one of those two glyphs, so this one pair of globs covers all four
opener shapes at once, still anchored to the `"delta":"` key itself so an unrelated payload field
is never mistaken for the delta's own text. An opener split across two chunks' own deltas, with
neither half matching alone, still falls back to plain — a known, accepted limitation, since late
engagement only ever looks at one chunk's delta at a time, never a cross-chunk reassembly, before
deciding.
