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

The gate loads `test_helper` before `test_timings`, so SimpleCov can observe the
timing library. A timing rerun uses `--only` for a unit file or Minitest's class
filter for one Varar document, and a failed subprocess fails the check. Mutation
reruns also require a successful process and a fresh report. An id missing from
the report's verdict lists stays unresolved, even when its summary counts kills.

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
the lifecycle order in its body. Where a human supplies a behavior from instinct,
an agent needs explicit scaffolding to reproduce it. Each agent-extra harness is
defined by reference to the human behavior it mirrors. Two mechanisms:

- **Eval**: a recorded check that running a procedure on a known input yields a
  conforming artifact. It mirrors the human behavior of *inspecting your own
  finished work against the standard before calling it done*. No eval suite ships
  in 2.0. Code does this check instead: `validate-intent`, doctor, and the checks
  `scripts/end-intent` runs at close.
- **Hook + instruction**: constrains an agent's reasoning at runtime. A trigger
  that fires on a runtime event and injects a steering instruction. It mirrors the
  human behaviors of *knowing the lifecycle order*, *feeling when to save state*,
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
(the context-full savepoint is the felt-savepoint behavior bound to a second
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
`restore-intent-v1` writes its own entry. Plastic runs no version control command (intent 390):
`scripts/maintenance-run` makes the change and its receipt on disk, then prints the `git add`
and `git commit` instruction for the closer to run by hand. A hand edit that moves content
records its entry the same way; `plastic
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
`outcome.md` has no disposition to echo, and a ruling of intent 219 forbids ever inventing one, so the warning
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
violation. It processes every store in one invocation by default (all stores already live under
the single `~/.plastic` home, so a cross-store write is still one home and, once the closer runs
the printed instruction, one scoped commit), unions with any existing hand-edited file content
so a manually added id is never dropped, and skips (never aborts on) any intent dir holding a
fresh delivery lock, reporting the skip. It writes no `revisions.md` entries: the tool modifies
no intent directory, only one store-level table per store, so 197's receipt-before-write rule
(which covers tools that structurally edit an intent's own files) does not apply here, and
writing one would mean editing every touched Completed intent directory, which the standing rule
that completed intents are immutable forbids. Plastic runs no version control command (intent
390): the diffable exclusion file itself is the receipt, and `maintenance-run` prints the commit
instruction for the closer to run by hand.

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

### the tri-graph kernel: built, not wired (intent 394)

Stage 1 of the tri-graph build landed the kernel under `scripts/lib/plastic/`. It has the
command line, routines, code and agent workflows, the four end values, the routine run row,
and a graph layer with one table, `routine_runs` in `work_graph.db`. The live command line
under `scripts/lib/cli.rb` still serves every command, and the kernel tests run in a process
of their own because both define some of the same constant names.

Stage 4, intent 399, added the work graph command set to the kernel's command table. Stage 5,
intent 400, added the knowledge graph command set. Both sets are described below. When the
live command line retires, the separate test process ends. See
[the contributor architecture page](contributing/ARCHITECTURE.md) for how a routine call runs.

### the work graph command set (intent 399)

`scripts/lib/plastic/cli/table.rb` routes 20 work graph commands against `work_graph.db` and
`knowledge_graph.db`: `node add`, `node remove`, `node claim`, `node release`, `node done`,
`node fail`, `node park`, `node answer`, `edge add`, `edge remove`, `intent spec`, `intent
rule`, `auto start`, `graph check`, `graph ready`, `graph show`, `intent show`, `intent
brief`, `status`, and `next`. See [architecture](architecture.md#the-work-graph) for the node
and edge state machine and the ruling/spec mechanics; this section covers the four read
commands stage 4 added on top of them.

`StartAuto.delivery_started?` checks both active status and a live auto lock held by the
calling session before skipping the write. The foreign live-lock gate still runs first.
`AddEdge` and `RemoveEdge` clear a failed result before retrying the write. Their gates
still report why an edge could not be added or removed.

`Commands::IntentShow` and `Commands::IntentBrief` are kernel routines (`workflow
:code_show_intent` and `:code_show_brief`): each refuses (exit 1) an unknown intent id through
a `gate`, then a `read` step prints from `context.retrieval` alone, so neither command writes.
`ShowBrief` marks a ruling superseded by checking whether any other ruling's `supersedes`
field names it (`rulings.filter_map(&:supersedes).to_set`), and lists the node and edge
command usage by calling `.usage_line` (from the `Declarations` module) on the 10 command
classes it requires directly. No dynamic class lookup from a command name takes place.

`Commands::Status` is a plain `CLI::Command`, not a routine, because it sweeps every store
under the Plastic home (`scope.known_slugs`) rather than one scoped store: it opens each
store's graphs in turn (`Graph.open(home:, store: slug)`) and prints its open and active
intents with their node counts by state (`Graph::IntentRow`, `Graph::NodeCounts`).

`Commands::Next` picks a live intent through `Graph::NextPick`. Closed intents are
excluded even if a lock remains after an interrupted closure. With several candidates,
the harness gets instructions to choose one. With no open work, the next command is none.

`Graph::DeliveryAction` supplies the actions used by next, brief, ready, and check.
Ready nodes lead to claim; failed nodes lead to release. Empty graphs hand planning to
`AgentWorkflow`, claimed nodes remain with their worker, and parked nodes request the
owner's answer. Completed graphs lead to `intent end` for explicit acceptance.

`IntentEnd` chains prerequisite checks, an agent verification handoff when records are
missing, and closure. `CompletionEvidence` accepts a JSON object with every exact done
criterion as a key and nonempty evidence text as its value. Paths resolve within the
selected intent folder, including a check after resolving symbolic links. The judge
attests to the evidence; Plastic does not execute the verification.

`CompletionWriter` stores the criterion snapshot, evidence, judge, outcome hash, session,
and timestamp in `completions`. It commits that row with the delivered status and closure
time in the work database, then releases the delivery lock in the home database. A repeat
call preserves the first completion record and retries cleanup. Imported done intents
remain closed without gaining an invented attestation. `node done --repair` explicitly
records verification for an already done node; it preserves the node's attempt count.

`graph.json` is a generated view. Sync up skips it, direct Reader import refuses it,
and sync down or graph show renders it from rows. Legacy import skips graph.json too;
its node and edge state can only be created through the graph commands.
