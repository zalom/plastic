# Plastic Internals

This is the deeper companion to the README's "How Plastic Works" section. The
README states the idea; this document explains the operational mechanics: how
Plastic makes work come out the same shape no matter who or what produces it,
and which scripts, hooks, and checks hold that shape in 2.0.

Status note for 2.0: no workflow skills ship. Intent 372 replaced the last ones with
`plastic` commands and `plastic help` chapters. `skills/` keeps only the shared
`_decision-tables.md`, which the installer places in `~/.plastic/`. Every section above
the last one describes 2.0. The 1.x skill design lives in one place, the final section,
"History: the 1.x skill design". For command usage, run `plastic help COMMAND`; the
chapters under `docs/help/` print through `plastic help TOPIC`.

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
the alternating Folgezettel rule, get one answer). A prose instruction to
"write a good spec" does not pass: two brains will produce two different shapes.
Everything Plastic constrains is built to pass the paper test.

## the-determinism-breakdown

A 1.x audit sorted every user-facing surface into three classes: deterministic-now,
mixed, and brain-loose. Most of the loose surfaces were prose skills, and none of them
ship in 2.0. The audit and its counts are in the history section at the end.

In 2.0 code owns the form of the executable layer: the `plastic` commands (their table is
`scripts/lib/cli/table.rb`), the scripts under `scripts/`, the hooks, the frontmatter and
directory schema, and the templates under `templates/`. What stays free is the prose a
brain writes inside those forms.

Seven agent role files ship in `agents/`: `plastic-enforcer`, `plastic-executor`,
`plastic-node-work`, `plastic-node-verify`, `plastic-node-research`,
`plastic-primary-advisor`, and `plastic-secondary-advisor`. They are handoff contracts,
not free-prose producers: each names what it consumes and produces. The installer copies
`agents/*.md` into the Claude and Hermes agent directories and renders each one as TOML for
Codex. The manifest tracks the installed files, so they prune on update and uninstall. The team model is `plastic help agent-architecture`.

## the-harness-system

No hook gates an edit on its content or stage in 2.0. Intent 302 removed the edit-path gates, the create gate,
and the stage-transition gates. No `PreToolUse` hook remains: the `call-budget` guard was
removed on 2026-09-24, and a node's call budget is now a sentence in its input that the
subagent honors itself. The `record` hook writes the savepoint line, refreshes
the lock heartbeat, and updates the day ledger. Doctor checks and the close checks in
`scripts/end-intent` report what the gates once blocked (intent 308).

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

Convention ships in two places. `PLASTIC.md` (installed at `~/.plastic/PLASTIC.md`) is the
always-on core: the small set of rules primed at every session start. A dedicated Minitest
test, `test/plastic_core_budget_test.rb`, holds it under 200 lines, 1,600 estimated tokens,
and 8,192 bytes. That test is the regrowth guard: two prior splits (intents 13b, 127) each
shrank the file once, with nothing holding the boundary. Longer doctrine lives in the
chapters under `docs/help/`, which `plastic help TOPIC` prints.

**Layer 2: agent-extra harnesses.** An AI agent lacks a human's innate senses: it
does not feel fatigue, does not sense when working memory is full, does not carry
the lifecycle order in its body. Where a human supplies a behaviour from instinct,
an agent needs explicit scaffolding to reproduce it. Each agent-extra harness is
defined by reference to the human behaviour it mirrors. Two mechanisms:

- **Eval**: a recorded check that running a procedure on a known input yields a
  conforming artifact. It mirrors the human behaviour of *inspecting your own
  finished work against the standard before calling it done*. No eval suite ships
  in 2.0. Code does this check instead: `validate-intent`, doctor, and the checks
  `scripts/end-intent` runs at close.
- **Hook + instruction**: constrains an agent's reasoning at runtime. A trigger
  that fires on a runtime event and injects a steering instruction. It mirrors the
  human behaviours of *knowing the lifecycle order*, *feeling when to save state*,
  and *leaving yourself a note when too tired to continue*. In 2.0 no hook gates
  an edit on its content or stage; the hooks record state, inject context, and cap a
  dispatched node's tool calls.

**The three constrainable points.** A brain step has exactly three points where
form can be constrained, and the mechanisms partition them:

1. **input-steer**: the input, before or while the step runs. That is
   hook + instruction (inject a rule).
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
live in `scripts/lib/savepoint.rb` (intent 303).

State-from-ledger (intent 81) makes the ledger the read-once answer to "what stage, and is it
done", so a resuming agent reads `savepoint.md` first instead of probing which files exist. The
grammar adds these line classes to intent 34's artifact-landing milestones, all keyed by
a `(stage, milestone)` pair for idempotency (`Savepoint.savepoint_recorded_pairs`):

- a **born `What` line**, stamped by `new-intent` at creation (not left to a hook firing), so
  even a freshly parked future intent carries the first bookend deterministically;
- an **`Exec  started` line**, which the `record` hook appends when a real `checklist.md`
  lands (`Savepoint.append_exec_started`);
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

`revisions.md` is a sibling per-intent ledger of structural maintenance. It records each
move-and-record change: the misplaced section, file, or ref, where it came from, the rule it
broke, and its prior content. `scripts/lib/revisions_writer.rb` (`RevisionsWriter`) appends
one entry per change for `project-links`, `rebuild-graph`, and the `rebuild-savepoint` tool;
`restore-intent-v1` writes its own entry. `scripts/maintenance-run` commits the change and its receipt as one
scoped store commit. A hand edit that moves content records its entry the same way; `plastic
help maintenance-and-revisions` has the format. The file exists only when maintenance
happened, so its presence is itself the signal.

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
dropped, not fabricated). `plastic roadmap log SLUG EVENT "TEXT"` calls `append` through
`scripts/roadmap-savepoint`. `RoadmapQueue` reads the ledger's newest line to rank roadmap
liveness, purely as a read. `INDEX.md` stays the single
status writer throughout; the ledger, like the intent-dir one, is sugar, never a source of truth.

The roadmap read path (intent 148) sits on top of that ledger. `scripts/lib/roadmap_queue.rb`
(`RoadmapQueue`, constructor-DI and hermetic: clock and paths injected, no eval, no ENV or global
config seam; a thin `scripts/roadmap-next` CLI wraps it, both registered in
`InstallerCore#core_files` and covered by a hermetic test) is the one roadmap reader. `plastic
next` and `plastic continue` read its queue mode through `scripts/lib/cli/frontier.rb`; its which
mode (`--which`, tie candidates for a human choosing) has no caller left now that the dashboard
is gone (intent 392), and stays exercised only by `test/roadmap_queue_test.rb`. It does two
things: liveness-ranks the tier's `roadmaps/*.md`
(a `delivering` or `blocked` entry wins, else the newest ledger or `## Log` timestamp, read
through `RoadmapSavepoint.ledger_path_for`), and within the winning roadmap selects the frontier
batch. When the roadmap's `## Graph` section carries edges, the frontier is the first
topological layer of that graph holding a dispatchable or in-flight entry (intent 336).
Otherwise the frontier batch is the first batch, top to bottom, holding a `queued` or `delivering`
entry; that batch's `queued` entries in file order are dispatchable (the head is next), a
`delivering` entry marks the batch in-flight and gates the next batch, a `blocked` entry is surfaced
but does not gate, and `delivered`/`abandoned` entries are settled. Every frontier token is
reconciled against INDEX.md before classification and INDEX wins on any mismatch, so an intent
INDEX already shows Completed or Abandoned can never be dispatched. The CLI emits JSON with a
`state` field (`dispatchable`, `in_flight`, `exhausted`, `none`, or `tie`) and a
`dispatchable_queue` array, plus `in_flight`, `blocked`, and `tie_candidates`. It runs in two
modes: queue mode (the default, for the loop) breaks ties
deterministically (newest ledger line, then slug ascending) and flags `tie: true`; which mode
(`--which`) returns `tie_candidates` instead of breaking the tie. The design is file-based throughout (roadmap `.md`, the 134 ledger, INDEX.md),
DB-ready but not DB-dependent: `RoadmapQueue` is the single seam a future 147 DB-backed read
swaps behind without changing either caller. A sibling seam covers ranking itself: dispatchable
candidates are value-ordered by an injected `ranker:` (default `FileOrderRanker`, today's file
order), reported as `ranking_strategy` in the payload, so intent 173's decision-systems
recommendation can replace the ordering rule without reworking parsing, frontier detection, or
the rest of the JSON contract.

A companion rule keeps the intent-dir ledger itself honest. `Savepoint.savepoint_phantom_lines`
(intent 134) is pure and disk-only, no lock or session resolution and no writes, matching
intent 52's decoupling precedent: it flags a `savepoint.md` line that disk evidence contradicts,
in three classes: a file-landing milestone (built from the same map `savepoint_milestone` uses)
whose file is absent or still a sentinel placeholder; a duplicate `(stage, milestone)` pair (the
later occurrence is the one flagged); or a state line, `How  started` or `Exec  started`, whose
stage prerequisite (the PRECEDING stage's real artifact, not its own, since a `started` line
legitimately fires before its own stage's file is real) is absent on disk. The bug-131 lock
clobber and the 124a out-of-band merge are the two live precedents this guards against: either
can leave a phantom or dropped line that nothing previously detected. `doctor.rb`'s
`check_done_signals` carries a `savepoint_truthful` advisory (pass when clean, warn and never
fail, mirroring `signals_complete`) that runs the detector across every intent dir the check
already visits. Nothing rebuilds a ledger on its own. For a live (INDEX Active) intent the
repair is `Savepoint.rebuild_savepoint`, which doctor's fix hint names; no command wraps it for a
live intent. A terminal
(Completed/Abandoned) intent is immutable: doctor reports and stops, and the 124a manual
Done-bookend repair (rebuild the skeleton, then re-append the terminal line from git or mtime
evidence) stays reserved for an explicit human grant.

Some `savepoint_operational` gaps can never legitimately close: a terminal intent with no real
`outcome.md` has no disposition to echo, and 219 D6 forbids ever inventing one, so the warning
would otherwise recur forever. Intent 274 gives each store a `doctor-exclusions` file, sibling to
that store's `INDEX.md` (`~/.plastic/stores/global/doctor-exclusions` for the global store,
`~/.plastic/stores/<slug>/doctor-exclusions` for a project; a legacy home keeps it beside
`~/.plastic/INDEX.md` and `~/.plastic/projects/<slug>/INDEX.md`), recording knowingly-exempt
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
message always merges in the honest count and the file's path once any exclusion applies, and
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
carries (`plastic help maintenance-and-revisions`). It is enforced by
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
buckets, and the file path merge into `savepoint_operational`'s message and `details` exactly the
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

Session resolution feeds the record hook and the lock (intent 52). Claude Code does not
export a session id env var into the hook environment; it passes `session_id` on the hook
stdin JSON. A launcher such as `hooks/record` pipes stdin unchanged to its Ruby script
(`scripts/hook-record`), and the Ruby script parses `session_id` out of the JSON. `Arm.resolve_session` takes the first non-empty of three
sources, in precedence order: the explicit stdin `session_id`, the `CLAUDE_CODE_SESSION_ID`
environment variable, and a derived `auto-<digest>` key (a short SHA256 of `store/intent_id`).
The derived key is deterministic, so a session-less arm and a later session-less check resolve
to the same session key, and a null session can never be persisted to `delivery.lock`.

Leftover cleanup happens at install and update, not at arm or disarm: `InstallerCore#distribute`
deletes every `store/.tmp/*/current` file and every `plastic-<session>--<id>.json` file sitting
in an injected tmp directory, by name alone, never opening or parsing a candidate.

`IndexEntry.match` and `IndexEntry.active?` (`scripts/lib/index_entry.rb`) are the one shared
matcher for the INDEX `## Active` line shape (`` `- [ID <sep> Title](path)` ``, where `<sep>`
is a real em dash or a plain hyphen on READ; every write still emits the real em dash), used by
both `end-intent`'s own INDEX-move parser and any caller asking whether an intent is still
active.

`plastic continue` does not read the intent ledger. It prints the project's store root, its
active intents, and its liveliest roadmap with that roadmap's frontier, then one next step:
the frontier's step when a roadmap exists, else `plastic intent show ID` for the first active
intent. `plastic intent show ID` prints that intent's state screen.

`doctor.rb` has four scopes:

- **`--core`**: binary pass/error only. Walks agent registration and core files
  (hooks, scripts, PLASTIC.md, VERSION, version match) and compares each
  file's content against its SHA256 in the install manifests. The global manifest
  (`~/.plastic/manifest.json`) covers PLASTIC.md and global scripts; the agent-side
  manifest (`~/.claude/plastic/manifest.json`) covers hooks, the shared
  `_decision-tables.md`, and the installed `agents/` role files, so `--core` SHA-verifies the role files too.
  Agent registration also runs an `agents_exist` check that passes when at least one
  `plastic-*.md` role file is present in the harness agent directory. The
  installer writes both manifests on every install or update. `--core` skips all
  store inventory walks so it returns in well under a second. Result is binary: exit 0
  on pass, non-zero on error, never a warning.

- **`--store [global|<slug>]`**: three-state (pass / warn / fail). Walks store state:
  intent well-formedness, INDEX sections, conventions, and link validity. Without an
  argument it checks all stores; `global` checks only the global store; a project slug
  checks only that project's store.

- **`--intent ID`**: three-state, one intent only, never a store sweep (intent 222).
  `verify-intent` runs it, and `end-intent` runs it as its self-check at close.

- **Full run (no flag)**: three-state. Walks every check category (global store,
  conventions across all intents, agent registration, core files, project stores,
  deprecations, runtime, display). This is what `plastic doctor` runs. After every
  `plastic update`, the core check runs by default and the full run runs with
  `--full-doctor`. Both are informational: they print the report but do not block or
  revert the update.

The `display` category (intent 331e) holds four checks. `display_hook_registered` (defined in
`scripts/lib/doctor_core.rb`, the SessionStart boot path) catches the MessageDisplay hook
missing from settings.json, registered to a foreign command, or registered but pointing at a
launcher that is missing or not executable; it is the only display check `--core` runs.
`display_hook_paints`, `display_not_defeated`, and `display_surfaces_documented` (all three in
`scripts/doctor.rb`, never the boot path, since they need `Open3`/`Timeout` to spawn a real
subprocess) run only in the full doctor. `display_hook_paints` replays a shipped fixture
(`templates/display-fixture.md`) through the INSTALLED launcher and expects a painted (ANSI)
screen back; when a known defeater is active (`NO_COLOR`, or `display.ansi_screen: false`) it
reports a pass naming the defeater instead of failing, since a deliberate setting is never a
broken hook. `display_not_defeated` is the check that actually warns about those defeaters, one
warning per active setting, and `display_surfaces_documented` confirms
`docs/reference/harness-adapters.md` still names all three surface classes (see its own
"Surfaces" section).

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
read-only: it prints that repair, and the user or agent runs it.

`plastic feedback "TITLE"` (intent 174) follows the same engine-in-lib, thin-CLI shape as
`doctor.rb`: `FeedbackReport` in `scripts/lib/feedback_report.rb` is a constructor-DI
engine (redact secrets, fill the version token, resolve a collision-safe report
path, cap the encoded URL at 7500 bytes with a page-one-plus-marker overflow), and
`scripts/feedback-report` is the thin CLI the command runs, with the report body read
from standard input. The report is saved as a draft, and the user opens the printed URL
to send it.

`hook-session-start` calls `--core` in-process (reusing the `Doctor` class, no second
process spawn) to drive the boot banner on every session start (intent 36a).

The hook surfaces that banner on two channels from a single `BootBanner` renderer (intent 54):
`hookSpecificOutput.additionalContext` (added to the model's context) and the top-level
`systemMessage` (rendered in the user's terminal, and re-fired on `/clear`). The banner is
binary: success produces one line, error produces one line with a prompt to run a doctor.
The error line still names `/plastic-doctor`, a 1.x skill that no longer ships; the
working command is `plastic doctor`. This is a known gap in `scripts/lib/boot_banner.rb`.
Sharing one renderer means the visible line and the model-facing line cannot drift.

`hook-capture` follows the same two-channel shape for the report roster (intent 392, replacing
the dashboard). When the prompt is exactly `continue` (ignoring case and surrounding spaces),
it runs `report-screen state --all` against the working directory's store (the project store,
or the global store when the directory maps to no project) and adds that plain-text roster to
`additionalContext`, then emits the same roster painted with `--ansi` as the top-level
`systemMessage`. It degrades silently on any failure (subprocess, empty output), so a broken
or slow `report-screen` call never crashes `UserPromptSubmit`.

## what-exists-today-vs-what-is-missing

The 1.x harness inventory counted gates, skills, and eval files that no longer ship. The
history section at the end summarizes it.

In 2.0 the harnesses are the ones this document describes. Templates under `templates/` fix
the form of every lifecycle file, including `spec.md` and `outcome.md`. Scripts write and
check artifacts: `new-intent`, `validate-intent`, `scaffold-intent`, `verify-intent`, and
`end-intent`. The hooks registered in `scripts/lib/hook_registry.rb` record state and inject
context. Doctor reports what is off. No eval suite or eval runner ships, so nothing replays a
recorded eval against a produced artifact.

### qmd registration and reindex flow

The optional qmd search integration mutates its index only on Plastic lifecycle
events, and one helper (`scripts/lib/qmd_sync.rb`, exposed as `scripts/qmd-sync`
with verbs `detect`, `register`, `reindex` (with an `--async` variant), `status`,
and a read-only `search`) does all the work by delegating to the qmd CLI. Each
trigger lives at a fixed point:

- **install and project creation**: `plastic install` registers every store as a QMD
  collection (`register_with_qmd`, a no-op when QMD is absent); `plastic project new`
  registers nothing. The session-start hook suggests `qmd-sync register --all` when QMD is present
  and the stores are not indexed yet.
- **intent delivery**: no public close path reindexes. `scripts/end-intent` stops at
  disarm, and its header says the reindex step stayed in a retired skill. This is a known
  gap. The internal `scripts/promote-session-item` runs `reindex` unless given
  `--no-reindex`. The sync
  `reindex` runs `qmd update` then `qmd embed -c plastic-<slug>` inline;
  `QmdSync.reindex_async` runs the same work detached via `Process.spawn` plus
  `Process.detach`, with output discarded, returning immediately. Both no-op when
  qmd is absent.
- **search**: the read-only `search "<terms>" [--store <dir>]` verb wraps
  `QmdSync.search`, scoping collections by `--store` (that store's collection plus
  `plastic-global`) or by CWD (`collections_for_cwd`), and prints ranked hits as
  `[<pct>%] <path> - <title>`. It no-ops cleanly (exit 0) when qmd is absent.
- **session start**: report-only. The boot path may report index status but
  never mutates it.
- **doctor**: the `qmd` category holds two checks. `present` passes whether or not QMD
  is installed, since QMD is optional. `collections` warns when a store's collection is
  not registered. Doctor does not check QMD's models.

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
  complete, non-zero with a report otherwise); `scripts/new-intent`, which validates
  the file it just wrote and exits non-zero when it is not born complete (`plastic
  intent new` runs it, then adds the intent's line to INDEX.md); and doctor's
  read-only conventions checks. Doctor's `frontmatter_fields` check is
  repairable through its `fix_hint` (the intent-19a pattern: doctor never writes;
  it prints the repair and the user or agent runs it), and a `frontmatter_valid` check flags
  malformed `sources` or `chain`. There is no `--fix` flag on `doctor.rb`.
- **Section structure (intent 60b)**: the validator also carries
  `SANCTIONED_SECTIONS` plus a pure `validate_sections`, merged into `validate`, so
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
  `--audit-path`): loads every store `StoreDiscovery` finds (the global store plus each
  project store), builds the maps, runs the transform per
  store, emits a per-store before/after audit grouped by kind (dedupes, I3
  resolutions, I1 backlinks, cross-store repoints/collapses, drops), then writes the
  changed frontmatter back. Pure Ruby (no bash). It runs no git itself;
  `maintenance-run --tool rebuild-graph --apply` wraps it in one scoped store commit with
  its `revisions.md` receipt. `~/.plastic` is never pushed.
- **Doctor's `graph_cross_store_resolution` check**: the i1/i3/i4 checks
  (`graph_invariant_checks`) deliberately treat a `store:id` ref as out-of-scope and
  validate only its shape, so a well-formed ref at a relocated or deleted target was
  invisible. The new check RESOLVES every cross-store ref against the full store
  family (relocation-first) even under `--store` scoping (only the REPORTED findings
  are filtered to the scoped origin), flagging dead and relocated-stale refs
  alongside i1/i3/i4. Its fix hint points at `scripts/rebuild-graph`.

## sanctioned creation path (intent 60b)

Intent 60 enforced the born-complete OUTCOME but not the PROCESS: an agent can
bypass `plastic intent new` and hand-author intent files with the same Write
primitive the command's script uses. Process-purity is unprovable (the script and a
hand-author look identical at the tool layer), so the achievable targets are the
INVARIANT (every intent file is born complete and structurally sanctioned) plus
the ERGONOMICS (the sanctioned path is the cheapest action an agent can take).
Two pieces deliver that.

- **`scripts/new-intent` (the one-call scaffolding contract).** A single invocation
  allocates the id via `folgezettel-id` (root, or a branch of `--parent`), creates
  `<store>/<id>--<slug>/` plus `actions/` and `resources/`, renders the
  born-complete intent file from `templates/intent.md`, writes the sentinel
  placeholder lifecycle files, wires the reciprocal `[[id]]` links, and
  self-validates with `IntentValidator` (exit non-zero if not born complete). It
  does NOT touch INDEX.md, git, or project creation. `plastic intent new` is the
  thin wrapper: it resolves the store from the project scope, passes `--parent`,
  `--sources`, and `--tags` through to one `new-intent` call, then adds the
  intent's line under `## Active` in INDEX.md.
- **Section-structure arm on `IntentValidator`.** `SANCTIONED_SECTIONS`
  (`## Intent`, `## Context`, `## Outcome`, `## Insights`, `## Links`, in order)
  plus a pure `validate_sections(body)` flag any unknown top-level `##` heading and
  any missing sanctioned section. `### Decisions` is the only sanctioned `###`
  subsection and is OPTIONAL (added after brainstorming), so its absence is never
  flagged. `validate` merges the section findings into the frontmatter result so
  every caller gets both checks from one call; `new-intent`, the `validate-intent`
  CLI, and doctor's read-only `section_structure` check all share this one
  definition so it cannot drift.

Portability (D9): the `new-intent` CLI is the lever, and it works on any harness. No
hook blocks a hand-authored intent file in 2.0; `validate-intent` and doctor's
`section_structure` check report one.

## delivery scripts (intent 213)

`AGENTS.md` states the classification rule: a step becomes a script only when its output is
a pure function of already-committed artifacts (spec.md, plan.md, checklist.md, outcome.md,
test results, the diff). Everything else stays judgment and stays with the agent. Intent 213
applied that rule with thin CLIs over `scripts/lib/` modules. Three of them remain:
`scripts/scaffold-intent`, `scripts/verify-intent`, and `scripts/exec-worktree`, which
finishes the code worktree. `scripts/end-intent` runs the same backfill as
`scaffold-intent` at close. The arm step is `plastic auto take ID`.

`scripts/scaffold-intent` is one CLI with one verb, `backfill` (its `spec`, `checklist`, and
`outcome` subcommands were removed in 2.0, intent 308). It runs `BackfillIntent`
(`scripts/lib/backfill_intent.rb`), the writer `scripts/end-intent` runs at every close: each
of spec.md, plan.md, `actions/ACTION_1.md`, and outcome.md that is missing or still the
placeholder is written from the record (the intent file, the checklist, the diff on the
intent's own worktree), every judgment section keeps the template's stub, and a file with
hand-written content is never touched. `end-intent` then runs doctor's per-intent structure
check as a self-check that reports and proceeds; the exit-6 refusal is gone.

Before that backfill runs, `end-intent` calls `scripts/lib/outcome_report.rb` (`OutcomeReport`,
intent 339): for an intent with a `graph.md`, it generates `outcome.md` from the graph, the
`nodes/` files, and the node ledger - `## Delivered` rows are done work nodes labeled by node
id, `## Verification` cites the ledger's typed evidence fields, `## Graph diff` names any
planned-but-not-done, undeclared, retried, or stale node, and `## Findings` renders the intent
record's `### Findings` under `## Insights`. Only into a file that is missing or still the
placeholder, and only when the generated text passes both `OutcomeGuard` and the hollow-report
gate; when it would not, the write is reverted and the close falls through to the backfill
above unchanged. `scripts/outcome-report` is the same generator's standalone CLI, for
checking or regenerating the file outside a close.

`scripts/verify-intent` merges doctor scoped to the intent, the added-line em-dash diff guard
(the first standing implementation of that check), a diffstat, and an optional
caller-supplied suite command into one verdict. It does not invent a project test-command
config. The doctor scan includes the `intent_ticks_lag` warning (intent 329): a WARN when the
savepoint's `Commit` ledger has entries and no checklist item is ticked.

## store layout and the stores move (intent 370)

Fresh bootstrap creates `stores/global/store` and `stores/global/INDEX.md`. Legacy data
(`store`, `projects`, `INDEX.md`, or `roadmaps` at the home root) keeps bootstrap on the old
layout until explicit migration. Bootstrap on an already migrated home never recreates `projects/`.
The context-budget benchmark seeds its fixture through the same store path resolver, so it
measures active intents in the layout produced by the real installer.

The four rows in `varar/store-layout.md` bind to `test/varar/store_layout.steps.rb`.
They pack once per test process, isolate every home and harness configuration, check
legacy data and backup preservation, and verify repeated migration refusal. The Varar
test loader checks that all four cases remain discoverable, so a removed or unparsed
table cannot silently drop this coverage. These rows make no model calls.

`scripts/lib/store_layout.rb` is the one place that turns a home and a slug into a store path.
`Plastic::StoreLayout.moved?(home)` is true when `stores/` exists. Every script asks it for the
global root, a project root and the list of project roots, so no script joins `"store"` or
`"projects"` by hand.

`scripts/lib/stores_move.rb` does the move for `plastic migrate stores`. It works in this order:

1. It refuses when `stores/` exists, when a fresh `delivery.lock` is held, or when the copy
   directory exists.
1. It copies the home to `~/.plastic-before-stores-move`.
1. It moves `store`, `INDEX.md` and `roadmaps` to `stores/global/`, and every child of
   `projects/` to `stores/`.
1. It rewrites the old paths in `config.yml`, in the QMD `index.yml`, and in the path columns
   of `knowledge_graph.db` and `references.db`.

The command makes no commit, and it leaves the copy for the owner to remove.

## project store provisioning

A project could be registered in `projects.yml` yet have no store on disk, which
left a store-less project that qmd could not register and doctor could only warn
about. Store creation was an inline `mkdir` duplicated across skills. The fix is
one shared definition of store creation that creation and repair both consult.

- **Single source of truth**: `scripts/lib/store_provisioning.rb` is the only
  definition of how a project store is made (mkdir the store at
  `~/.plastic/stores/{slug}/store` through `StoreLayout.project_root`, or
  `~/.plastic/projects/{slug}/store` on a legacy home, then write-if-missing `.gitkeep`
  in the store, and `INDEX.md` from `templates/index.md` and `project.yml` from
  `templates/project.yml` beside it). It
  is injectable (`plastic_home`, `package_root`), hermetic, idempotent, uses no
  eval, does no global-constant injection, and performs no qmd mutation, mirroring
  `intent_validator.rb`. The logic was migrated from the orphaned
  `InstallerCore#bootstrap_project_store`, which is now removed.
- **Consumers sit on top of it**: the `scripts/provision-project-store` CLI (exit
  0 on success, non-zero with a report when the slug is unregistered or on usage
  error); `plastic project new`, which runs the verb after `projects.yml`
  registration; and doctor's read-only `project_store_dir` check, which warns and
  prints `provision-project-store {slug}` as its fix.
- **Scope boundary**: the provisioner is pure filesystem. It never mutates qmd and
  never edits `projects.yml`. Registering the store with qmd is a separate, optional
  `qmd-sync register --store` step that no-ops when qmd is absent.

## per-agent model resolution and installer application (intent 116)

Every agent in `agents/*.md` pins an explicit model and effort in its own frontmatter.
The five lifecycle and node roles use a Claude Code alias and `effort: medium`, tiered by
role: `plastic-enforcer` and `plastic-node-verify` are `opus`; `plastic-executor`,
`plastic-node-work`, and `plastic-node-research` are `sonnet`. None is ever `inherit` and
none is ever Fable by default. Fable is named in three places, and only three: the
auto-mode advisory notice below (about the human's main session, never a dispatched
subagent), an explicit `agents.models.<name>` config override, which is honored as written
for a dispatched subagent when one is configured, and the shipped defaults of the two
consultation agents. Primary Advisor and Secondary Advisor are not
lifecycle stage roles. Neither is ever dispatched by the auto pipeline. Both use Fable on
Claude Code and Astra on Codex; Primary uses medium effort, and Secondary uses high effort.

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
  `scripts/read-config --harness` resolves the requested model namespace and translates
  shipped aliases to OpenAI IDs for Codex. It resolves effort from the matching harness
  namespace and defaults every agent to medium.
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
  line. A literal override also receives medium effort unless `agents.efforts.codex.*`
  overrides it. An empty value emits nothing. Scoping the Codex call to `harness:
  "codex"` is what closes the literal-model-id leak: a value set under the legacy flat
  form or `agents.models.claude.*` is claude-scoped only and is never visible to the
  codex-scoped resolution, so it can never surface in a generated Codex TOML `model`
  line. See [harness-adapters.md](reference/harness-adapters.md) for the full codex
  agent TOML contract.
- **Graph runtime contract**: `RunnerPolicy` resolves model and effort for the active harness.
  `RunnerDispatch` records both on `running`, and `scripts/node-run` passes both explicitly
  to `codex exec`. A research node can declare one Markdown report under `resources/`.
  The read-only node returns its content in YAML and `RunnerAbsorb` performs the confined,
  atomic write after validation.
- **Dispatch-time contract (belt-and-braces)**: because Claude Code reading
  frontmatter at dispatch time is a harness implementation detail rather than a
  contract Plastic controls, the enforcer's body tells it to resolve the target
  agent's model at every dispatch through the same chain
  (`read-config agents.models.<basename> --project <repo>`) and pass it
  explicitly as the dispatch call's model parameter, never relying on the
  dispatched role's frontmatter alone. Graph nodes get the same guarantee from
  `RunnerPolicy`, above.
- **Orchestrator advisory (not a gate)**: at auto-mode start, the enforcer
  recommends once that the user run the orchestrating main
  session on the best available thinking model (Fable, Opus, or whatever supersedes
  them). This changes no behavior and blocks
  nothing if ignored; it concerns only the human's main session, since dispatched
  subagents keep their pinned tier and never resolve to Fable, unless an explicit
  `agents.models.<name>` config override names Fable for that role, in which case the
  override is honored as written. Primary Advisor and Secondary Advisor are not lifecycle stage roles: the never-Fable rule governs
  stage agents only. Neither is ever dispatched by the auto pipeline; they are
  consultation roles summoned deliberately by the user or the main session. Both default
  to Fable on Claude Code and Astra on Codex. Primary uses medium effort. Secondary uses high.

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
- **Reports and removes, creates nothing** (intent 390): `Arm.worktree_block`
  resolves the slug from the intent dir, derives the code worktree's path and
  branch through `Worktree.paths`, and reports `provisioned` as whether that
  path already exists on disk -- `code` and `code_branch` name the expected
  workspace whether or not it exists yet; only a store-only project (no repo
  resolves) leaves them blank. Neither `Arm.arm` nor `Arm.repair` runs git.
  `Worktree.release(delivery)` still removes an existing worktree, prunes, and
  clears the block when `provisioned` was true; it is a no-op otherwise, since
  a path that was never created is nothing to remove.
- **Unified `PLASTIC_HOME` seam** (intent 169): every CLI-script and hook entry
  point resolves its sandbox override from the single env var `PLASTIC_HOME`
  (`read-config`, `hook-capture`, `qmd-sync`, `provision-project-store`,
  `validate-intent`, `doctor.rb`, `install.rb`, `hooks/check-update`); an older,
  differently-named env var that only `read-config` read was hard-cut, not
  aliased. Holding this seam is a level mismatch: the env var names the
  plastic_home ROOT (`~/.plastic`), and scripts turn it into store paths through
  `StoreLayout`, while `worktree.rb`'s
  `home:` kwarg names the OS HOME (the PARENT of `.plastic`) and computes
  `plastic_home = File.expand_path(File.join(home, ".plastic"))` internally, so
  threading the env value straight into `home:` would yield a
  `~/.plastic/.plastic` bug. `Arm.home_for` therefore never reads the env: it
  derives `home` from the already-sandboxed intent directory's store path
  (anchored on the `.plastic` path segment, via the pure `Worktree.home_from_store`
  helper), falling back to its `home: Dir.home` default only when the store is
  blank or unrecognized. This closes a real incident where a sandboxed board,
  with no override, planted a git worktree in the operator's actual
  `~/.plastic` back when `Worktree.provision` did the resolving; deriving from
  the store trusts the already-sandboxed value over the ambient environment,
  and the same derivation now guards every path `Arm.worktree_block` computes.
  The derivation only engages when the store's plastic-home segment is
  literally named `.plastic` (a sandbox home like `/tmp/x/.plastic` works; an
  arbitrarily named root does not, and it falls back to the passed `home:`).

- **Foreign locks refuse with exit 3**: `plastic-lock` exits 3 when the lock
  belongs to someone else: `arm` on a held, stale, or excluded lock, `fix` that
  cannot repair a held or stale lock, `release` by a session that is not the
  owner, and `reclaim` on a fresh lock. Each refusal prints a hint that names a
  public command (`plastic auto lock status ID`); `Arm.stale_hint` carries the
  stale wording. `arm` on an unreadable lock exits 1 and names `plastic auto
  lock fix ID`. `Arm.repair` stamps `run_mode: auto` on a lock it rebuilds from
  nothing, and keeps the mode of a lock it keeps. `plastic auto take` passes
  `--harness`, `--agent`, `--model`, and `--thread` through, infers the
  `claude` harness from `CLAUDE_CODE_SESSION_ID`, and prints the lock and the
  worktree unless `--json` is given. The runner's re-arm hint is
  `plastic auto take ID`.

- **Three distinct evidence layers and bounded delegate history** (intent 108a):
  the controller record proves whole-intent authority; a registered delegate record
  authorizes one child session under that controller; a claim record identifies
  one current writer for one artifact among already-authorized sessions. Delegate
  activity status (`active`, `finished`, or `failed`) is observational and does not
  remove the session from the string-array authorization list. A delegate remains
  authorized until a separate removal mechanism exists. Finished and failed activity
  history is capped at the 20 most recent terminal entries.

## per-artifact claim tokens (intent 111)

The delivery lock above resolves ownership at the whole-intent grain: it answers
who may work an intent at all, not who may write one specific lifecycle file
right now. Two writers that both hold the lock, whether two registered
delegates or two subagents that inherited one `CLAUDE_CODE_SESSION_ID`, can
write the same file, so nothing arbitrates a
same-time write to `spec.md`, `plan.md`, `checklist.md`, or the intent file
itself. Intent 111 adds a second, lighter layer underneath the delivery lock.
Since the gates were removed in 2.0 (intent 302), no write path checks a claim: a
claim is a cooperative signal that writers and orchestrators read through
`plastic-lock`.

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
  the collision-90 failure mode, where an over-armed lock froze unrelated
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
  or corrupt). On a true result, the claim yields to the current writer rather
  than blocking it: `plastic-lock claim` takes a stale claim over and says so on
  stderr, and `plastic-lock status` reports each claim with whether it is fresh. Absence of a
  claim is plain dormancy, not a fail-open condition. Intent 112, which planned
  a maintenance lock on top of this test, was abandoned: no maintenance lock
  exists, and a terminal intent directory is edited only on an explicit owner
  grant.
- **CLI and visibility.** `plastic-lock claim --artifact <name>` acquires a
  claim (exit 1 and names the holder when one is already held, even by the
  same session; takes over a stale claim automatically); `plastic-lock
  release-claim --artifact <name>` frees it. `plastic-lock status` lists every
  claim file, each with its artifact, owner session or delegate, acquired-at
  time, and whether it is still fresh, so an orchestrator checking status before
  respawning a helper can see a live writer on an artifact and skip the respawn.

## doctor: Codex hook registry vs. dispatcher agreement (intent 200)

`codex_hooks_registered_check` (`scripts/lib/doctor_core.rb`) only diffs `~/.codex/hooks.json`'s content
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
extraction (`codex_dispatcher_gate_names`, its `STATE_HOOKS` constant plus its
top-level `case gate` statement's `when "..."` labels), never a hand-kept duplicate in
`doctor_core.rb` (a duplicate would be the exact bug this check exists to catch, one level up).
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
registered and no longer does (`edit-gates`, `bash-gate`, `code-gate`, `create-gate`,
`links-gate`, `lock-gate`, `savepoint-pre`, `qmd-search`, `retrieval-gate`,
`model-instructions`, `opus-manual`, `continue`, `future-intent-check`, `auto-arm`,
`gate-check`, `power-tools`), seeded from git history. It exists because an old install's settings.json can carry an entry for a
launcher `events` no longer mentions, and nothing else can prove that entry was ever Plastic's.
It is purge-only and stays disjoint from `claude_launcher_names`: merging retired names into
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

- intent 298: the session-start and post-tool hooks, and the heartbeat
  under `.tmp/<session>/`, and capture and record.
- intent 300 (delivered): `scripts/session-commit`, which appends one `Item` or `Note`
  savepoint line per commit. See "the session branch model and session-commit" below.
  Only `plastic session commit` runs it; the record hook stopped spawning it on 2026-09-24.
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

## session-commit records, it never commits (intent 390)

`scripts/session-commit --cwd <dir> --summary <text> [--ref REF]` is how a verified checklist
item gets a permanent record. It runs no version control command. It never shells to `git` or
`gh`, so `scripts/lib/session_git.rb`, its `runner:`/`gh_runner:` seams, and the flow-resolution
and pull-request-body logic that used to live behind it (intent 300) are gone. What replaced
them is two plain steps: append one savepoint line, then print the instruction that names the
actual commit for the caller to run.

**Recording.** `SessionLedger.open_day` opens the day ledger the same way it always has. The
event is always `Item` -- there is no git outcome left to degrade it to a `Note` over -- with
the summary text unchanged, or `"<summary> (ref <REF>)"` when `--ref` is given. It is recorded
against the same store `--store`/`--plastic-home` (or their defaults) already resolved to;
being inside a registered project changes only the printed instruction, never which store the
line lands in.

**The printed instruction.** Outside a registered project, or when `--cwd` resolves to no
known project, the instruction points at `plastic help completion-and-done` and names no
repository, since there is none to name. Inside a registered project, the instruction names
the project's path and says to commit there the way that repository's own `AGENTS.md` says --
Plastic does not restate a project's commit conventions, it points at the document that owns
them. `PullRequestTemplates.instructions(repo)` (see below) is appended below that: one line
per detected template, or, when none is found, a line pointing at
`plastic help completion-and-done` for what comes after the commit.

**`scripts/lib/pull_request_templates.rb`.** A pure, read-only file-glob check, no git or `gh`
call: `PullRequestTemplates.detect(repo)` globs for
`.github/pull_request_template.md`, `.github/PULL_REQUEST_TEMPLATE.md`,
`.github/PULL_REQUEST_TEMPLATE/*.md`, `docs/pull_request_template.md`, and
`.gitlab/merge_request_templates/*.md`, returning the paths that exist (deduplicated, since a
case-insensitive filesystem can match more than one of the GitHub globs against the same
file). `.instructions(repo)` turns each match into the exact command that uses it:
`gh pr create --template NAME.md` for a GitHub path, `glab mr create --template NAME` for a
GitLab one. Neither method runs `gh` or `glab` to check that either is installed; the command
they name is left for the agent, alongside everything else session-commit prints, never
Plastic itself.

**The CLI's fail-open guarantee.** `scripts/session-commit` wraps `SessionLedger.open_day` and
the savepoint append in their own rescues, and `main` carries a top-level one, so a store or
ledger failure (a read-only store directory, an installed layout missing `templates/`) degrades
to exit 0 with the instruction still printed, rather than a raw Ruby backtrace and a crashed
calling process -- the same exit-0-always contract intent 298's `record` hook already depended
on. The savepoint append does not depend on `open_day` having run: it calls
`FileUtils.mkdir_p` on the day directory itself first, so a damaged install that cannot open
the day ledger can still write its one savepoint line. Only a usage error (no `--cwd`, no
`--summary`) exits 2 and writes nothing.

**`plastic auto take` reports a worktree, it never creates one.** The companion half of this
cut: `Arm.worktree_block` (see the worktree-provisioning section above) computes the expected
code worktree's path and branch with no git call, and `scripts/lib/cli/commands/auto_take.rb`
renders them on the screen (`present`/`not yet created`, from `provisioned`) and, when a repo
resolves, prints the exact `git -C <repo> worktree add <path> -b <branch>` as the `next:` line
-- Plastic names the command, the agent runs it. A store-only project (no repo resolves) keeps
the previous next step, `plastic auto brief ID`, since there is no workspace to create.

## compaction thresholds and the compact-instructions block (intent 312)

Two config keys and one installed block tell a session when to compact and what to do
about it. Nothing in Plastic reads the keys at runtime: the harness reports how much of
the window is used, and the model acts on the installed block. The keys exist so a user
can retune the numbers that block states.

```yaml
context_offer_tokens: 150000    # offer a compaction
context_insist_tokens: 250000   # insist on one
```

They are absolute token counts, not percentages, and they resolve through the ordinary
`scripts/read-config` path (project, then global, then the `DEFAULTS` in that script).
Intent 296's D38 settled the numbers from `research--context-thresholds.md`: models are
reliable only to roughly 50 to 65 percent of advertised context, and the mechanisms
behind that are architectural, so a percentage that is right at a 200k window would let
five times as many raw tokens pile up before firing at 1M. The three places the numbers
live (the `DEFAULTS` hash, `templates/config.yml`, and `InstallerCore#bootstrap`'s seeded
config) are pinned equal by `test/compact_instructions_test.rb`.

Intent 355's n5 (D7) lowered both numbers again, from 350,000/500,000 to 150,000/250,000:
a live session that let the window run from 434,000 to 506,000 tokens spent a third of
that window on 41 calls before it compacted. The three-way pin above still holds; only
the shipped values moved.

The block itself is `CompactInstructions::BODY` in `scripts/lib/compact_instructions.rb`,
installed into `~/.claude/CLAUDE.md` as a marked section:

```
<!-- BEGIN PLASTIC COMPACT hash:<12 hex> -->
...the block...
<!-- END PLASTIC COMPACT -->
```

Intent 363 added the first line of that block: a Claude Code import, `@~/.plastic/PLASTIC.md`.
Ruling D43 makes `PLASTIC.md` the only instruction text Plastic puts in a session, and this
import is how the harness reads it. The path names the installed copy under the Plastic home,
because a bare `@PLASTIC.md` would resolve against `~/.claude`, which holds no such file.

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


## meter-watch: the rate-limit meter on a timer (intent 355, n5, D6)

`scripts/meter-watch` reads the owner's rate-limit cache
(`~/.plastic/.cache/rate-limits.json`, written by the owner's live statusline hook, not
by anything in this repo) and writes `~/.plastic/.cache/meter-state.json`, so a session
watches one small file instead of every session parsing the cache and re-deriving the
thresholds for itself. `MeterWatch` (`scripts/lib/meter_watch.rb`) does the reading and
classifying; the CLI is a thin wrapper.

The state file carries `state`, `five_hour`, `seven_day`, `resets_at`, and `checked_at`.
`state` is one of:

- `ok` -- below every threshold
- `reduce` -- `five_hour` at or above `meter.reduce_at` (default 55)
- `stop` -- `five_hour` at or above `meter.stop_at` (default 85), or `seven_day` at or
  above `meter.weekly_stop_at` (default 97)
- `resume` -- the previous state was `stop` and `resets_at` has passed
- `stale` -- the cache is older than two ticks (40 minutes at the default 20-minute
  tick), so its numbers are not trusted
- `unavailable` -- no cache file exists

The three thresholds resolve from `meter.reduce_at`, `meter.stop_at`, and
`meter.weekly_stop_at` in config, the same DI-first pattern as everything else here:
`MeterWatch.new` takes `home`, `now`, `cache_path`, and a `renamer` for the underlying
atomic write, never ENV.

The state file is written through `AtomicWrite` (temp file, then rename) and only when
`state` actually changes, so a watcher never fires on a tick that changed nothing and a
crash mid-write can never leave a torn file behind.

`meter-watch --install-timer` writes a LaunchAgent plist under the given `--home`
(`Library/LaunchAgents/com.plastic.meter-watch.plist`) that reruns the tick every 20
minutes. It never calls `launchctl`; it prints the `launchctl load` command for the
owner to run by hand. The Plastic installer never calls `--install-timer` on its own --
starting a background job is the owner's decision, not the installer's.

## living-document

This is a living document. When Plastic's architecture, lifecycle, conventions,
hooks, or harnesses change, this file and `architecture.md` must be
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

The general skill-authoring guides moved to the `skill-creating` and `skill-evaluating` skills in [zalom/agent-skills](https://github.com/zalom/agent-skills); `docs/skill-authoring.md` keeps the Plastic-only rules.

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
| agent catalog | every `agents/*.md` frontmatter `name` + `description` value | reported |
| boot injection + skill catalog | the two above | **under 17,500**, a 313 ratchet, lower it, never raise it |
| standing surface | core block + boot injection + both catalogs | **under 3,608**, an intent 363 ratchet that only moves down |
| median skill body | the median `SKILL.md` body, frontmatter excluded | reported |
| doctrine working set | boot injection + `skills/_decision-tables.md` + the median skill body | reported against the 15,000 target, with its gap |

Bytes are the budget; two token estimates ride along, a word-based one (`words * 1.3`, the same
arithmetic as `scripts/lib/skill_lint.rb`, so the bench and the linter can never disagree) and
`bytes / 4`. Neither is a tokenizer. Rows that are arithmetic over other rows print `-` for the
word estimate rather than a number that looks measured and is not.

In 2.0 no `skills/*/SKILL.md` ships, so the skill catalog is empty and the median skill body
is 0. The rows stay so that a skill added later is measured.

**Why the working set is reported and not enforced.** Its median term steps by about a
kilobyte whenever a skill is added or removed, so a ceiling there would turn the suite red on a
step nobody ruled. The bench prints the number and its gap to the 15,000 target on every run.
The ceilings stay on the core block, the boot injection, the boot injection plus the skill
catalog, and the standing surface, which every boot reads and the bench measures exactly.

The bench is a maintainer tool. It lives under `bin/` beside `bin/test`, is deliberately absent
from `installer_core.rb`'s manifest, and is never installed into `~/.plastic`: it reads this
repository's own files and a fixture it builds, so it has no meaning on an installed copy.

## the ScreenPaint registry, and late-capable engagement (intent 331a)

Before 331a, `scripts/lib/screen_paint.rb` recognized a screen's opening line against one
hard-coded `OPENER_RE`, and `MessageDisplay` (the `hooks/message-display` adapter) let only
chunk 0 decide whether a message was a screen at all - a prose-first or fenced reply left that
decision final, wrong, and unpainted for the rest of the message.

**The registry.** `ScreenPaint.register(kind, opener:, paint: nil)` adds one entry (a Regexp or
a callable) to a module-level registry; `ScreenPaint.kinds` lists every registered name, and
`classify`/`paint` consult the registry instead of a single constant to decide whether a line
opens a screen. `paint:` is optional and defaults to the shared pipeline everything else in the
file already implements - no shipped kind carries its own palette; the registry's only job is
that a new kind's opener is recognized without editing this file, and that a kind CAN supply its
own paint lambda on the rare day one needs one. The five shipped kinds (`intent`, `state`,
`roster`, `delivered`, `delay`) register at the bottom of `screen_paint.rb` itself, decomposed
from the original `OPENER_RE` into its `"## "`-prefixed half and its bare-glyph half, so the
set of lines recognized as an opener is unchanged. A caller-added kind lives in its own file,
`scripts/lib/screens/<kind>.rb`, calling `ScreenPaint.register` on load; `scripts/report-screen`
glob-requires `lib/screens/*.rb` (sorted, tolerating an absent or empty directory), and
`installer_core.rb`'s glob-derived `screen_files` (mirroring `template_files`/`hook_files`)
ships that file to an installed `~/.plastic` - "add a file, not a diff" is otherwise false for
an installed copy, not just an in-repo one. Intent 331b's `plan` kind (`report-screen plan
<intent_dir>`, the pre-delivery report) is the first caller-added kind built this way, in
`scripts/lib/screens/plan.rb`.

**Late-capable engagement.** `MessageDisplay#handle_chunk_zero` and `#handle_later_chunk` both
scan their own chunk's delta, line by line, for the first line that opens a screen
(`split_at_opener`) - not only at chunk 0, and not only at the very start of a delta. A chunk
that engages (the FIRST one whose own text carries an opener, whatever its index) writes the
shared `SCREEN` decision file with ITS OWN INDEX as a decimal integer (replacing any `NOSCREEN`,
which is no longer a final answer once a later chunk engages), returns the text before the
opener as `displayContent`, and buffers the opener onward at its own index. The final chunk -
routinely a separate process - reads that index back off `SCREEN` and waits, and later splices,
only from there, rather than burning its whole poll budget on chunks before the engaging one
that were never buffered at all (they already reached the terminal, unmodified, through the
ordinary passthrough path). A lone fence line immediately wrapping the opener - one right before
it in the engaging chunk's own prefix, one right after the painted region in `finalize` - is
dropped; a fence in an earlier, already-displayed chunk is never touched, and an unrelated code
block elsewhere in the message survives verbatim. `hooks/message-display` mirrors this at the
shell layer: a chunk is handed off to Ruby, whatever its index - chunk 0 included, not only a
later one - when its own delta value contains a bare `▶` or `✔` anywhere, raw or `\u`-escaped -
every shipped opener contains one of those two glyphs, so this one pair of globs covers all four
opener shapes at once, still anchored to the `"delta":"` key itself so an unrelated payload field
is never mistaken for the delta's own text. An opener split across two chunks' own deltas, with
neither half matching alone, still falls back to plain - a known, accepted limitation, since late
engagement only ever looks at one chunk's delta at a time, never a cross-chunk reassembly, before
deciding.

**The decision marker (intent 331a1).** Claude Code's concurrent chunk processes race chunk 0's
own Ruby boot (about 150 ms), and a later chunk judged before SCREEN or NOSCREEN exists used to
fall back to the cheap shape test and pass through plain whenever it wasn't. `hooks/message-
display` now stakes a `PENDING` file with builtins the moment chunk 0 is handed off, before Ruby
starts; a later chunk that finds the message directory polls for the real decision whatever its
own shape looks like, since a decision is certainly coming once `PENDING` is there. A `PENDING`
whose mtime is already older than that chunk's own poll budget reads as NOSCREEN (fail open,
checked once, never inside the poll loop, since mtime never changes). `MessageDisplay#budget_ms`
scales the poll budget with the chunk's own index - base `wait_ms` plus `index_wait_ms` per
index, capped at `max_wait_ms` - so a chunk deep into a long streamed message waits long enough
for a decision that is certainly on its way, and `write_screen`/`write_noscreen` both remove
`PENDING` the moment they run, so it is never both there and stale at once for long.

## the report roster (`report-screen state --all`, intent 392 replacing the dashboard)

The dashboard (`scripts/dashboard.rb`, its `--screen` renderer, `scripts/lib/dashboard_screen.rb`,
`templates/dashboard-screen.md`, and the `:dashboard` `ScreenPaint` kind) is gone. The one place
that filled the same job, a glance at every store's active work, is now `report-screen state
--all <store_root>`: `plastic status` names the stores and their active intent ids (see
"status and the report roster" above), and `hook-capture` runs `report-screen state --all`
against the working directory's store on a bare `continue` prompt (see the `hook-capture`
section above). `docs/help/human-report-contract.md` names the roster's own column shape and
capped-list behavior; this section does not repeat it.

No rendered header across the report-screen family reads "What" any more: the id column is
"Graph ID", the title column is "Intent", every Steps table reads `Step | Status | Detail`,
the plan screen's own reads `Step | Action | Detail`, Risks read `N | Risk`, and the
`delivered` screen's own three tables read `Row | Detail | Proven by`, `Kind | Detail |
Source`, and `N | Need | Reason` (intent 331f, D5/D7). `ReportScreen.fit_screen(text, limit:
115)` is the one shared pass every public render entry point calls last: a fitting screen
returns byte-identical, an over-limit table shrinks its widest shrinkable column first (floor
8, a progress-bar column never shrinks, ties break leftmost), and a row that is still over the
limit after every column hits its floor truncates on a word boundary as a last-resort backstop.
No rendered row exceeds 115 visible columns; the bound is measured on the whole
pipe-delimited row, never on one cell, since a cell short enough on its own can still drift the
row past the bound once a progress bar, a lead, and the separators are added.

## roadmap screens: the roadmap verb, `RoadmapQueue#roadmap`, and the Log fallback (intent 331c)

A roadmap gets the same three reports an intent has (`report-screen roadmap <roadmap.md>
plan|state|delivered [--ansi] [--store-root <dir>]`), read entirely from files already on disk:
the roadmap `.md` itself, `INDEX.md` (which always wins on status), and the roadmap's own
savepoint ledger.

**One reader, never two parsers.** `RoadmapQueue#roadmap(path)` is the public counterpart to the
private `queue`/`which` the auto loop already calls: for ONE roadmap file it returns the slug,
path, grouping label (`RoadmapSavepoint.grouping_heading`, "Batches" or "Waves"), the batches with
each entry's id, title text, and INDEX-reconciled status, and the frontier
(`RoadmapQueue`'s own private `frontier_for` - a screen never re-derives which batch is live).
Intent 336 (G3) taught `frontier_for` to follow a roadmap's own `## Graph` section when one
carries real edges, falling back to wave order otherwise; `roadmap(path)` reads whichever path
`frontier_for` takes with no change of its own. `ENTRY`'s regex gained a capture group for the
entry's own title text between the id and
the status separator; `parse_waves`' group indices moved with it, and `test/roadmap_queue_test.rb`
stayed green unchanged, since nothing public in `queue`/`which` reads that new group.

**The events a screen reads.** `RoadmapSavepoint.ledger_entries(roadmap_path)` parses a roadmap's
paired `.savepoint.md` into `[Time, event, detail]` triples in file order - the format
`RoadmapQueue`'s own liveness ranking already parses inline, now a public reader so a screen never
re-derives the "<iso>  <event>  <detail>" line shape a second way. When a roadmap carries no ledger
file at all (an archived roadmap moved before intent 134 shipped a ledger for it, `manual-first.md`
among them), `ReportScreen.roadmap_events` falls back to the `## Log` lines, classified through
`RoadmapSavepoint.classify_event` (made public; same `KEYWORD_TABLE`, no second vocabulary) and
timestamped from each Log line's own date and time - so a fully-shipped roadmap with no ledger file
reads its real closed time, not `in progress`.

**The delivered meta line's placement is load-bearing.** `ScreenPaint.classify` recognizes `:meta`
only on the line immediately after the opener (`idx == opener_idx + 1`); the
`templates/report-roadmap-delivered.md` template's meta placeholder sits on the line directly under
the title with no blank line between, or `ScreenPaint.paint` returns `nil` and the whole screen
falls back to plain.

**The Merged cell** matches a line only when the entry's id is its SUBJECT - the first
whitespace-delimited token of the ledger detail, never a whole word anywhere in it, because a
real ledger line can name one entry's id as its subject and a second entry's id in passing (a
post-execution-review fix: the second entry's row was picking up the first entry's sha). Among
subject-matching lines, one is read when the ledger's own event is `merged` or the detail matches
`RoadmapSavepoint::KEYWORD_TABLE`'s own merged pattern - a real per-entry merge is sometimes filed
under a different event word (`dispatched`, in the real `codex-fixes` ledger, because the rest of
the line carried other dispatch news) - and refused when the event is `handoff` or the detail
matches the table's handoff pattern. The sha is still the first hex token of 7-40 characters
carrying at least one digit, the same shape a real `git` short or full hash takes, distinguishing
it from an all-letter word that happens to be valid hex.

**Paint kinds.** `scripts/lib/screens/roadmap.rb` registers `:roadmap_plan`, `:roadmap_state`, and
`:roadmap_delivered` (331a's registry, a file rather than a diff to `screen_paint.rb`), openers
that are strict subsets of the shipped `intent`/`delivered` openers. No `paint:` lambda: the
palette stays `IntentScreenAnsi`'s shared pipeline, exactly like every shipped kind before it.

## the node input command (intent 338, G5)

A node agent is stateless (327 D45): its whole input is its node input. `DataBoundary`
(`scripts/lib/data_boundary.rb`) owns the trust boundary a node input is built over. A data
block is opened by `<<<PLASTIC-DATA:<token> label="..." source="...">>>` and closed by
`<<<END-PLASTIC-DATA:<token>>>`, one token per node input, the first twelve hex characters of
the SHA-256 over the node input's raw payloads joined by a newline - content-derived rather than
random, so the same node built twice produces the same bytes and the same hash (spec D4).
Every payload is escaped independently of the token (spec D5): a literal opening or closing
marker inside a payload is rewritten with a backslash after the angle brackets, so a resource
carrying the node input's own marker still cannot close its block even if the token leaks.
`label` and `source` marker attributes are not payload text and are sanitized separately, by
a whitelist rather than the payload escaping rule (spec D5a, the plan review's blocking
finding): every character outside `[A-Za-z0-9 _.,:#/@+=-]` becomes `_`, truncated to 200
characters, so neither a quote nor a newline in a hostile `sources:` entry can break a
marker line. `DataBoundary.estimate_tokens` is `(bytes / 4.0).round`, the one arithmetic
every budget in this delivery is spent in (spec D6).

`NodeInput` (`scripts/lib/node_input.rb`) gathers the five blocks 327 section 8 fixed, in
a caller-independent order (spec D2): the node, the ledger, the record, the knowledge hop,
and where to work. Blocks 1 and 5 are instruction, authored for this node by the orchestrator
and by the project record; blocks 2, 3 and 4 are retrieved text and are wrapped as labeled
data sharing the node input's one boundary token (spec D3). The node block reconciles the node
file against `graph.md`'s declared nodes, refusing rather than rendering an empty block for
an id the graph does not declare. The ledger block carries every transition line for the
node in file order (torn lines marked, never counted as evidence), predecessor evidence read
from `graph.md`'s edges (never the node envelope, which 327 D41 removed `needs` from) and
counted only from an attributed well-formed `done` line, the lease from `--holder`/`--expires`/
`--model` or the last `running` line or `lease: none` plus a stop directive (spec D9, C7), and
landed commits after a reclaim through an injected git runner that is never invoked without a
`reclaimed` line (spec D14, C11). The record block carries only `## Intent` (the floor, never
cut), `### Decisions` (falling back to a top-level `## Decisions` when the nested one is
absent) and the last three `## Insights` entries, with a kind-aware exclusion of any
`### Findings` subsection for a verify node (spec D12, C23) anchored to the `## Insights` body
itself, so a `### Findings` living under `## Context` (intent 109's own shape) is never
touched. The knowledge hop is one level and never transitive (spec D13): each frontmatter
`sources:` entry contributes only its `## Outcome` and its `### Decisions` (or, when the
record carries none - about half the store, intent 327 among them - that source's own
`spec.md` `## Decisions`), capped at `hop_tokens` with a truncation note, and disabled
entirely at `--hop-tokens 0` (224's kill criterion, spec D7).

Assembly (same file) renders the five blocks, measures the budget over the fully rendered
bytes with markers included, and applies the C28 cut ladder only as far as needed and only
when a step actually shrinks the render: drop the hop whole, cut Insights to the last one,
cut Decisions to the last five (spec D8). The node, ledger and where-to-work blocks are never
touched by any cut. Still over budget after the third cut: no file is written, exit 4, and
the exact `node-transition ... --state needs_decision --field question="..."` command is
returned, naming the oversized block and its token count so the owner knows what to shorten.
Attempts are numbered from the node's prior `running` lines, plus one when a lease is
supplied by flag (a new dispatch), floored at 1, overridable with `--attempt` (spec D11,
C21); the node input lands at `attempts/<node>--a<N>.input` (a `.input` extension, not `.md`,
so QMD's `**/*.md` collection glob never re-indexes a node input's wrapped payloads back into
search results). Rebuilding an attempt is a no-op when the bytes are unchanged and a refusal
(exit 5) otherwise, unless `--force` is given. The hash is the SHA-256 of the file's own
bytes on disk, first twelve hex, printed and never embedded in the file (spec D10); it is the
value `node-transition running --field input=<sha>` takes.

`scripts/node-input <intent_dir> --node <id>` is the CLI, shaped like `node-transition` and
`validate-work-graph`: 0 success, 2 usage (not an intent directory, missing `--node`, or an
unknown node), 3 an unreadable/unparsable graph, node file or record, 4 overflow, 5 an
attempt conflict (spec D17, shared exit-code family so a runner routes on the same codes
across both node commands). On success it prints a parsable summary
(`path=... sha=... tokens=... hop_tokens=... attempt=...`) and the exact `node-transition
running` command to record, both of which intent 340's runner parses.

## trusted publishing over OIDC (intent 347)

`@zalom/plastic` used to depend on a long-lived npm access token sitting in one maintainer's
`~/.npmrc`. On 2026-09-08 that token had expired, the alpha.18 release stalled at the publish
step, and the package reached the registry only the next morning after a manual `npm publish`
from a detached checkout of the tag. `.github/workflows/publish.yml` closes that failure mode
structurally: no npm token exists anywhere, on any machine or in any GitHub secret.

**The trigger (intent 376).** A push to `alpha`, `beta` or `main` is the release. The workflow
reads the version from `package.json`. When the tag for that version exists, it stops. Otherwise
it runs the suite and the guard, packs one archive, creates the tag and the GitHub release
with `plastic.tgz` attached, and publishes that same archive to npm. To release, change the
version in the three version files and push the branch. `install.sh` at the repository root
downloads the archive of the latest stable release, unpacks it under `~/.local/share/plastic` and links
`~/.local/bin/plastic`.

**The mechanism.** The publish job is granted `id-token: write`. The npm CLI detects the OIDC environment, fetches a short-lived
token scoped to this repository and this exact workflow filename, and presents it to the
registry instead of an `_authToken`. The registry compares the token's claims against the
trusted publisher registered on npmjs.com and publishes only on an exact match. The trust is
pinned to the workflow file's name, not to a person: anyone who can push to a channel branch can
publish, and renaming `publish.yml` silently breaks every future release, which is why a test
pins the path.

**The guard.** `scripts/release-check`, a thin CLI over `scripts/lib/release_guard.rb`, runs
before the publish step. It asserts that the pushed branch publishes the channel the version
suffix names (`alpha`, `beta`, or `main` for a version with no suffix), that the three repo version files agree
(`ReleaseGuard.check`, `scripts/lib/release_guard.rb`),
and that the runner's npm meets the 11.5.1 floor OIDC requires, comparing version segments
numerically so `11.10.0` does not lose to `11.5.1` as a string. It writes the derived dist-tag
to `$GITHUB_OUTPUT` by appending, never truncating, so another step's output in the same file
survives.

**One dist-tag rule, one implementation.** `ReleaseGuard.dist_tag(version)` returns `alpha` for
an `-alpha` suffix, `beta` for `-beta`, `latest` for no suffix at all, and the raw suffix itself
(never `latest`) for anything else. The workflow's `--tag` argument is always
`${{ steps.guard.outputs.dist_tag }}`, never a literal, because the alternative - a second,
untested implementation of the same rule in shell - is exactly the kind of drift that would put
an alpha on `latest` and pull every stable user onto it at their next `plastic update`.

**The suite runs in the publish job.** The publish job runs `ruby bin/test` before the guard,
so a red suite stops the release before any tag, GitHub release, or npm publish.
`test/publish_workflow_test.rb` pins that order. `.github/workflows/test.yml` also runs the suite
on pushes and pull requests to `main` and `alpha`.

**The `npm` environment.** The publish job runs in the GitHub environment named `npm`, and its
URL points at the package page on npmjs.com.

## CLI adapter contract

`Legacy` captures child stdout for JSON commands and passes it to `Output` for
one final envelope. Child output remains an array of strings under
`result.output`; it is not presented as parsed domain state. Text commands retain
the existing script display. Usage errors, failures, and owner refusals keep their
exit codes and stderr diagnostics, with an error object for JSON callers.

`IntentProgress` reads lifecycle prerequisites and checklist items through the
existing screen reader. A direct step prints its first incomplete item without
starting the graph runner. A graph step uses the runner's ownership resolver
before dispatch. Lock inspection and search end with `next: none`.

`test/cli/release_contract_test.rb` exercises the actual executable with isolated
stores, including creation, screens, project scope, direct progression, graph
lock prerequisites, and blocked Future work.

`IntentStep` forwards graph returns, harness selection, and the explicit core-drift
override to the runner. `AutoTake` exposes the owner-approved inline override;
without it, a started conversation session returns refusal code 3. Lock screens
read `owner_session`, with the older `session` field as a compatibility fallback.
The renderer supports both the RDoc 7 constructor with options and RDoc 8's
keyword constructor, so an installed package does not depend on the development
bundle's RDoc version.

### Package and store safety checks

`bin/plastic` sets the package root from its own location. This prevents the
old updater's environment from routing a newly downloaded command back to an
older installer. The update and rollback subprocesses also clear that variable.
A successful subprocess is insufficient: the installed `VERSION` must equal
the selected target.

`InstallerCore` checks store-layout compatibility before either switch can
write files. `ProjectLinks` resolves audit paths through `StoreLayout` and
skips audit writes during previews. Packaged Varar scenarios exercise update
refusal, rollback refusal, and link previews separately for Claude and Codex.

### Close refusals shared with the dry run

`scripts/lib/untouched_scaffold.rb` decides whether an intent is still its
new-intent scaffold. The check is narrow on purpose. All four lifecycle files
must exist as untouched placeholders. There must be no ticked checklist item, no
action, node or graph file, and no savepoint line past What. The code worktree
must have no uncommitted changes and no commits past its base. When the
worktree cannot be read, the intent counts as worked. `end-intent` exits 8 on a
delivered close of such an intent, before any write.

`unmerged_refusal` in `scripts/end-intent` runs next, also before any write, for
a delivered close. `Arm.code_paths` names the code worktree and branch the
intent would have, whether or not the worktree exists. The check fails closed:

- When the code directory is the top of a real Git worktree, the commit at its
  HEAD must be an ancestor of the repo checkout's HEAD. This covers a renamed
  branch and a detached HEAD. A HEAD that `git rev-parse` can't read refuses.
- When the code branch exists, it must be an ancestor too, so a removed
  worktree doesn't hide unmerged work. A failed branch lookup refuses.
- When the repo checkout is detached, or is on the code branch itself, no
  other branch holds the code, so the close refuses. `target_refusal` checks
  this before each ancestry check.
- When `git merge-base --is-ancestor` itself fails, the close refuses the same
  as when the code isn't merged.
- When the repo has a `.git` entry but `git rev-parse --git-dir` fails there,
  the close refuses.

A refusal exits 9 and names the ordinary merge to run. `end-intent` never
merges. A store-only project and a repo path with no `.git` entry skip the
check. So does a code directory that isn't a real worktree and has no branch.
The dirty-worktree guard refuses that last case (exit 5) because it can't
inspect it.

`end-intent --dry-run` copies the intent to a scratch directory. It runs the
same outcome generation and backfill on that copy, then applies the
hollow-report gate (exit 7). The dirty-worktree guard is shared by the dry run
and the disarm step (exit 5). The dry run also refuses exits 8 and 9 exactly as
the real close does. `plastic intent end` names exits 7, 8, and 9 in its failure
message.

### Bounded display replay

`HookReplay.run_bounded` feeds the hook and reads its output through pipes.
It used scratch files before. On Snap Ruby the launcher's `ruby` could not use
those files, so the doctor paint check saw empty output and failed.

One deadline covers the whole exchange. It covers the launcher's exit, feeding
stdin, and draining stdout and stderr. A launcher can exit while a child it
started still holds the pipes, so waiting for the launcher alone is not enough.
A writer thread and two reader threads work at the same time, so large input or
output cannot block. The hook leads its own process group. When the deadline
passes, the whole group is killed and the pipes are closed. The chunk keeps the
output read so far, with a nil exit status. The bounded run writes no files.

### Command surface repairs

`IntentCommand#after_run` returns the `next:` command and its reason after the
script succeeds. `IntentStep` overrides it: when `RunnerCore.complete?` holds
for the intent's graph, the next command is `plastic intent verify ID`.
`RunnerDispatch` passes `HarnessAdapter.agent_type_for_kind` into the spawn
line, and `NodeInput` marks nodes without a worktree as read-only.

`RoadmapQueue` ranks a roadmap with a cyclic graph after every healthy one.
`roadmap-graph` reports graph ids no batch lists even when it also finds a
cycle. `plastic sync` lists a missing `work_graph.db` or
`references.db` under `build`.

## History: the 1.x skill design

This section describes Plastic 1.x and is not current behavior. It is kept so the
reasoning behind 2.0 stays readable. Nothing here ships in 2.0.

**The determinism audit.** A 1.x audit sorted all 93 user-facing surfaces into three
classes: 70 deterministic-now, 18 mixed, and 5 brain-loose. The deterministic ones were the
executable layer: scripts, hooks, tests, the frontmatter and directory schema, and the
templates. The looseness sat in prose skills that asked a brain to write an artifact with no
output template. The mixed ones were template- or script-backed skills with free-prose pockets,
plus two recorded `evals.json` files.

**Stage agents.** 1.x shipped one agent per lifecycle stage beside the enforcer and the
executor. The stage agents were removed in 2.0 (intent 304). The enforcer now writes the Why
and How itself.

**The harness inventory.** 1.x counted 23 harness entries: 7 hard-block, 10 soft-steer, and 6
advisory. The advisory ones included two `evals.json` files that no runner ever replayed. The
same audit listed 13 net-new harnesses to build, led by the `spec.md` and `outcome.md`
templates, which did ship, and a form-assertion eval runner, which never did.

**Three-tier conventions.** 1.x shipped convention in tiers (intent 223): `PLASTIC.md` as
the always-on core, held under 500 lines and 5,000 estimated tokens, and a shared conventions
skill whose chapters other skills loaded by path. 2.0 keeps `PLASTIC.md` and moves the longer doctrine into the
chapters that `plastic help TOPIC` prints.

**Gates.** 1.x hooks blocked writes: edit-path gates, a create gate, and stage-transition gates
checked the lock, the worktree, links, and the stage before an edit landed. Claims were checked
by those gates too. The gates were removed in 2.0 (intent 302). Doctor checks and the close
checks in `scripts/end-intent` now report what the gates once blocked (intent 308).

**Skill-era readers.** In 1.x, skills read the ledgers and acted on them: a savepoint skill
verified the ledger, a discovery agent ran after an intent was activated, a feedback skill filed
reports, and a doctor skill applied repairs. In 2.0 those jobs belong to `plastic` commands and
to doctor, which stays read-only and prints each repair.

**Releasing.** The 1.x releasing skill ran the release actions a project listed, including a
local `npm publish`. Plastic's own project used a workflow variant that confirmed and followed the
`publish.yml` run instead of publishing locally. Intent 372 retired the skill. In 2.0 a push to
`alpha`, `beta`, or `main` is the release.

**The publish suite step (intent 347, D7).** When trusted publishing first shipped, the
publish job ran no suite. The suite was red on hosted Linux runners for hermeticity reasons, so
gating a publish on it would have moved the release stall onto the runner. The suite ran only
before the tag was cut. The publish job has since gained the suite step, which runs before the
guard.
