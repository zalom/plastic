# Human Report Contract (the report screens, intent 317)

D15: the prose EM-to-CTO briefing this doc used to define is retired. The orchestrator now
prints one of these report screens, filled from the record by `scripts/report-screen`, never
written by eye:

- **`report-screen plan <intent_dir>`** - the pre-delivery report (intent 331b), printed once
  at the How boundary, before the executor is dispatched: Asked, Decisions, Steps, Mode,
  Reviewer, then the Steps table (Step, Action, What) and the Risks table.
- **`report-screen state <intent_dir> [--changed "<text>"]`** - the mid-delivery report. One
  intent's field table (Store, Status, Stage, Savepoint, Progress, Next, Insight) plus a
  `Changed` row naming what caused the print, and its Steps table.
- **`report-screen state --all <store_root>`** - the roster across every in-delivery intent,
  most recently changed first, then one collapsed block (Stage, Next, Changed, first three
  open steps) per intent.
- **`report-screen delivered <intent_dir>`** - the post-delivery report, printed once at close:
  Asked, Delivered (with a Proven-by column), Evidence, Needs you.
- **`report-screen delay <intent_dir>`** - printed only on request ("why did X take so long"):
  the delivery as a timeline plus the derived `Where the time went` line.
- **`report-screen session <tier_root>`** - the answer to an UNNAMED status ask ("where are we
  with delivery", "what is the status"): one `delivered` screen per intent this session
  completed, oldest first, then the `state --all` roster. Intent 330's ruling: a status ask
  answers with what actually shipped, not the in-flight roster alone.
- **`dashboard.rb continue|project <slug> --screen`** - the dashboard screen (intent 331d):
  Active, In delivery, Delivered, Roadmap, Sessions, Changed, then the Where-we-are and
  Where-we-go-next tables. A separate script from the other four (`dashboard.rb`, not
  `report-screen`), since it aggregates across a whole store or project rather than one
  intent; it prints on `continue` and on loading a project, not as a delivery trigger.

## Binding table (intent 331f)

Every skill that shows state names its own report verb, one row per skill and trigger. Each
bound skill's file carries the SAME rule next to its verb: print the screen as the first
characters of the reply, nothing before it, no fence, or the hook cannot paint it.

| Skill | Trigger | Verb |
|---|---|---|
| `plastic-intent-continuing` | project route (continue, load project) | `dashboard.rb ... --screen` |
| `plastic-intent-continuing` | a named intent | `report-screen state` |
| `plastic-intent-continuing` | "where are we" (a status ask) | `report-screen session` |
| `plastic-intent-continuing` | "why so long" | `report-screen delay` |
| `plastic-intent-continuing` | a roadmap route | `report-screen roadmap ... state` |
| `plastic-auto` | the How boundary, before the executor | `report-screen plan` |
| `plastic-auto` | each of the five triggers | `report-screen state` |
| `plastic-auto` | close | `report-screen delivered` |
| `plastic-intent-ending` | the close | `report-screen delivered` |
| `plastic-intent-speccing` | the action files are written | `report-screen plan` |
| `plastic-roadmap` | create | `report-screen roadmap ... plan` |
| `plastic-roadmap` | read | `report-screen roadmap ... state` |
| `plastic-roadmap` | close | `report-screen roadmap ... delivered` |
| `plastic-dashboard` | any invocation | `dashboard.rb ... --screen` |
| `plastic-intent-executing` | after the red commit, and after the suite | `report-screen state` |

## A roadmap's own three reports (intent 331c)

A roadmap gets the same pre-, in-, and post-delivery shape as an intent, through
`report-screen roadmap <roadmap.md> plan|state|delivered [--ansi] [--store-root <dir>]`:

- **`roadmap plan`** - the pre-delivery report: the Goal's first sentence, the batch (or legacy
  wave) count and intent count, the batch order, and when the roadmap was created; then the
  full entries table.
- **`roadmap state`** - the in-delivery report: Goal, a Progress bar over intents delivered of
  intents total (never batches), the frontier batch, who is delivering it and their lead, the
  next queued entry, and the last ledger event; then the entries table with each entry's own
  checklist progress and lead.
- **`roadmap delivered`** - the post-delivery report: a meta line (closed time, or `in progress`
  when the goal is not yet reached; intent count; duration) directly under the title, the
  delivered table with each entry's merge sha, and the `## Log` table.

Every cell traces to the roadmap file, `INDEX.md` (which always wins on status), the roadmap's
own savepoint ledger, or (falling back when no ledger file exists) the roadmap's `## Log` -
never a second parser: `RoadmapQueue`'s own public `roadmap` reader supplies every entry.

## The five triggers for `state`

Print `state` (one intent, or `--all` for the roster) on any of these; a checklist tick alone,
an executor's intermediate commit, or an agent going idle is NOT one of them:

| Trigger | Scope |
|---|---|
| A savepoint line lands (a stage boundary: Why, How, Exec started, outcome written, Done) | that intent |
| A review verdict returns (plan review or post-execution review), naming what it changed | that intent |
| A blocker or needs-input is logged | that intent |
| A merge or a release lands | that intent |
| The owner asks ("where are we", "state of X", "continue X") | all in delivery, or the one named |

`delivered` prints exactly once, at Completion. `delay` prints only when the owner asks why a
delivery took long.

Every verb prints the same plain Markdown on every harness (owner ruling 2026-08-31); where a
harness can paint it (Claude Code, through 316a's message-display hook), it substitutes a
painted rendering of that same output, never a different one, and no skill or script branches
on harness name to decide.

## Depth for small work

For small work in auto mode, only the How-boundary `plan` screen prints mid-flight (intent
331f moved this print off `state`, since there is no separate briefing per stage any more).
Larger work prints `state` at every trigger in the table above. This is a
depth cut, not a different report: the screen's shape never changes, only how often it fires.
A delivery still ends with `outcome.md` plus one `delivered` screen.

## One report per audience

A delivery produces exactly two artifacts: `outcome.md` (authored by `plastic-intent-ending`)
and one `delivered` screen at the End stage. No stage or skill restates a delivery already
written to `outcome.md`; point at it instead. Skills do not open with a banner that names the
skill or restates the intent id and name the owner just typed. Announce only what the reader
cannot already know: an error, a result, a choice with its reason, or a handoff.

## Boundary vs intent 74

Intent 74's report contract (`references/agent-report-contract.md`) is the INTERNAL,
machine-checked handoff from a dispatched specialist back to the orchestrator: a structured
envelope plus a per-role payload. This contract is the OUTWARD screen shown to the owner.
Different direction, different audience, different form. The orchestrator reads the intent 74
report and reflects it into the record (savepoint, outcome.md) that `report-screen` then
renders. The two never merge.

## Brevity: point, don't repeat

Surface rules are owned by the `writing-style` skill. This contract does not restate them. Its
job is naming which screen prints when, not the wording inside it - `report-screen` derives
every cell from the record (D14), so there is no prose left to style here.

## Emission: guided vs auto

In guided mode, `state` prints at each stage boundary and the human decides before the next
stage starts.

In auto mode, `state` prints at every trigger for larger work; for small work only the How
boundary's `plan` screen prints (see `## Depth for small work` above). The orchestrator takes
the go-ahead itself and moves on, except at the existing hard stops (destructive action without
a safe alternative, project-path confirm).

## Column vocabulary (D5, intent 331f)

Owner ruling 2026-09-05 11:05 UTC: "What" is never a column name, because What is a stage, not
a value. The id column reads `Graph ID`; the title column reads `Intent`. Every Steps table
reads `Step | Status | Detail` (the plan screen's own Steps table reads
`Step | Action | Detail`); every Risks table reads `N | Risk`; the Delivered/Evidence/Needs-you
tables on the `delivered` screen read `Row | Detail | Proven by`, `Kind | Detail | Source`, and
`N | Need | Reason`. The plan screen's Asked row prints the intent title before its first
colon, never the whole intent line. This applies to every screen the family prints: `state`,
`roster`, `session`, `delivered`, `delay`, `plan`, `roadmap` (`plan`/`state`/`delivered`), and
`dashboard`. `outcome.md`'s own `| Row | What |` heading is an AUTHORING convention inside the
file a human writes, never a rendered header, and stays unchanged.

## Width bound (D7, intent 331f)

No rendered row passes 115 visible columns. A long cell (the roadmap Goal, an intent title, an
Asked line) truncates on a word boundary with a single ellipsis; `ReportScreen.fit_screen`
shrinks a table's widest column first, floor 8, before it ever truncates a whole row.
