---
id: "331"
intent: "Reporting improvements V2: every report Plastic prints for work (per-intent pre-, in-, and post-delivery, roadmap, dashboard on continue and load project) reaches the terminal painted in the agreed colors and layout, bound to the skill that shows state, font inherited from the terminal; collects the 316/317 family, tests every delivery on the real display path, and roadmaps the fixes"
sources: ["316", "317", "330"]
chain: ["331a", "331b", "331c", "331d", "331e", "331f", "331g", "333"]
created: 2026-09-05
author: human
tags: ["project-plastic", "reporting", "tui", "screens"]
---

## Intent
Reporting improvements V2: every report Plastic prints for work (per-intent pre-, in-, and post-delivery, roadmap, dashboard on continue and load project) reaches the terminal painted in the agreed colors and layout, bound to the skill that shows state, font inherited from the terminal; collects the 316/317 family, tests every delivery on the real display path, and roadmaps the fixes

## Context
The owner watched the 316/317 family ship over five days and then saw plain, uncolored Markdown
tables in his terminal most of the time, laid out differently from the design artifacts. On
2026-09-05 he asked for one intent that collects the family, tests every delivery on the real
display path, and roadmaps the fixes, and ruled the target: every work report painted, per intent
(pre, in, post delivery), per roadmap, and for the dashboard on continue or load project, each
bound to the skill that shows state.

What the family delivered, in order:

- 316 intent screen: `scripts/intent-screen` fills `templates/intent-screen.md` from the record.
- 316a ANSI intent screen: `IntentScreenAnsi`, the MessageDisplay hook, the fail-open contract.
- 316a1 harness-agnostic TUI core: renderer core with per-harness adapters, plain is the floor.
- 317 delivery reports: `report-screen state|delivered|delay`, the human-report contract.
- 317a report screens paint and read their own records: the ScreenPaint seam, grammar engagement.
- 317a1 color mapping: full palette per screen kind, three-column field rows, 115-column width.
- 318 exact TUI rendering research: the ceiling (color yes, font and panel never).
- 322 Proven-by heading resolver: the delivered screen reads the matrix that owns a step.
- 330 status ask prints the session delivered screens: `report-screen session`.
- 311 day summary and 74 agent report: text reports outside the screen family.

Evidence gathered in this intent (`resources/evidence--display-path.md`): the installed hook paints
every screen that opens a reply (12 replays); across 142 transcripts only 28 replies carried a
screen in six days and 10 of those were prose-first or fenced; a live Claude Code 2.1.261 under a
pseudo-terminal shows the painted block in the normal view and plain bordered tables after Ctrl+O
or with prose first; day summary, dashboard, roadmap, and agent report have no grammar; the day
summary and session-start box are model-only. The catalog artifact of every printed form:
https://claude.ai/code/artifact/58f2d7b9-3bc8-4635-a229-fecedec3d9aa

### Decisions
Recorded in spec.md (D1 to D12); the roadmap `roadmaps/reporting-v2.md` orders the fixes.
## Outcome
(the result — implementation details, deliverables)

## Insights
(observations captured throughout — raw material for future intents)
2026-09-05T09:12:55Z · Why · orchestrator — Owner check 2026-09-05 09:12 UTC: the roster screen printed by this background session reached the agents view painted; owner's words: colored and aligned - exactly as I wanted. The bg-pty-host surface paints; the remaining plain cases are prose-first, fenced, grammarless reports, and the verbose view.
2026-09-05T11:22:17Z · Exec · orchestrator — Lock heartbeat finding 2026-09-05 11:35 UTC: leads armed with a derived key (CLAUDE_CODE_SESSION_ID unset) never refresh delivery.lock; 331d's lock read 76 min old while its lead was alive, and the 324/325/321/322 locks are 3170+ min old from dead sessions. The roster (ReportScreen.lead) prints any lock as a live lead; the roadmap and dashboard screens honor the 30 min lease and print idle. Reporting fix in 331f D6 (one freshness rule, stale · N min). The heartbeat defect is filed as its own intent.
2026-09-05T14:10:55Z · Exec · orchestrator — Process finding 2026-09-05 13:55 UTC: the 331f lead delivered the D8 colon ruling as branch plastic/331f2--title-colon-rule straight into alpha (a8b1bb3) with no intent record, then owned it; the orchestrator backfilled 331f2. Also: the full suite on alpha a8b1bb3 showed 1 failure with 15405 assertions on one run and 0 failures with 15409 on the next two, while the 331f1 lead was editing in its worktree; a test appears to read live state outside its fixture (hermeticity_guard scope worth widening).
2026-09-05T17:52:28Z · Exec · orchestrator — Hand-off 2026-09-05 17:40 UTC (orchestrator, owner clears the session): delivered 331a, 331b, 331c, 331d, 331d1, 331e, 331f, 331f2, 331f1, 331f1a; alpha at 2f3625a plus the 2.0.0-alpha.15 bump, published on the npm alpha tag and installed locally; catalog artifact republished; roadmap overview artifact https://claude.ai/code/artifact/75659a6f-a6fc-4dc5-8430-7e765ed5424c. Live captures on alpha.14: 10 of 12 shapes painted including prose-first and fenced; roster and session plain. After 331a1 on alpha.15: state paints, roster and session still plain, no leftover hook buffers, one painted title in the stream: the region ends early on a line the painter rejects. lead-331a1 holds a REVISE with a trace-first plan and appends findings to 331a1 Insights. Process findings this session: three intents closed before acceptance (closes need an accept node), one lead merged code without a record (331f2 backfilled), a stale staged revert was found in a worktree at close, and derived-key leads never refresh lock heartbeats (intent 333). Resume with: continue the reporting-v2 roadmap.

## Links
- [[316--intent-screen|The intent screen: one Markdown block printed on continue and on a state question, a vertical field table (Store, Status, Stage, Savepoint, Progress bar, Next, Insight) with a note per row, What-this-means bullets, and a Steps table with a status per step, filled by scripts/intent-screen from the record so no number is written by eye; standard record names only, Step N items with S1..SN shorthand]]
- [[317--end-of-work-report-screen|Delivery reports: a mid-delivery report (on a change worth reporting or on request; all in-delivery intents or one; structured as the state variant of the intent screen) and a post-delivery report (when an intent is delivered: outcome and every detail that matters afterwards; new design chosen from artifact options), both printed as screens, replacing prose reports]]
- [[330--status-prints-session-delivered-screens|Status ask prints the session's delivered work: whenever the owner asks where are we or what is the status, Plastic prints one delivered screen per intent completed in the current session (every store touched, in completion order) followed by the in-flight state roster and the What-this-means bullets, as one verb (report-screen session <tier_root> --session <id>) that the continuing skill and the auto skill route every status ask through, on every harness; owner ruling 2026-09-04]]
- [[331a--hook-engages-anywhere|Hook engages anywhere: the MessageDisplay hook paints a screen wherever it sits in the reply (prose before it passes through, a code fence around it is dropped), and ScreenPaint exposes one grammar registry so new screen kinds (plan, roadmap, dashboard) add an opener and a paint rule without touching the hook; the engagement census and the replay harness become tests]]
- [[331b--plan-screen-pre-delivery|Plan screen, the pre-delivery report: report-screen plan <intent_dir> prints Asked, the decisions count, the planned steps S1..SN from checklist.md with their action file, and Needs-you or risks from plan.md, as a screen with its own grammar and painted form; printed by the speccing and auto skills before Exec starts]]
- [[331c--roadmap-screens|Roadmap screens: report-screen roadmap <roadmap.md> plan|state|delivered prints the pre-delivery plan (goal, batches, entries with status), the in-delivery state (batch progress bars, delivering entries with their leads, next), and the post-delivery delivered report (batches shipped, versions, log) as screens with grammar and painted forms, read from the roadmap file, INDEX.md, and the roadmap savepoint ledger]]
- [[331d--dashboard-screen|Dashboard screen: dashboard.rb continue and dashboard.rb project <slug> print a screen (where we are, where we go next, live sessions) with its own grammar and painted form instead of Markdown prose, and the continuing skill and the load-project path print it as the first thing in the reply]]
- [[331e--doctor-display-check|Doctor display check: plastic-doctor verifies the MessageDisplay hook is registered for the Claude harness, replays one screen through the installed hook and expects a painted block back, warns when verbose mode or NO_COLOR would defeat painting, and the harness-adapters doc states which surfaces paint (Claude Code normal view), which are owner-verified (agents view), and which stay plain (Codex, claude -p)]]
- [[331f--skills-bound-to-reports|Skills bound to reports: every skill that shows state names its report verb and prints it as the first thing in the reply, with a contract test per skill (continuing: state, roster, session, dashboard; auto: plan before Exec, state at each trigger, delivered at close; ending: delivered; speccing: plan; roadmap: roadmap plan|state|delivered; dashboard: dashboard screen; session start on load project: dashboard screen), so a status ask can no longer be answered in prose]]
- [[331g--live-verification-and-release|Live verification and release: every screen (plan, state, roster, session, delivered, delay, roadmap plan|state|delivered, dashboard) captured painted from a real Claude Code session under a pseudo-terminal on the installed core, the owner confirms the agents view once, the captures land in 331's evidence file and the catalog artifact, and the alpha release that ships the family is cut]]
- [[333--derived-key-lead-heartbeat|Derived-key leads never refresh the delivery lock heartbeat: an enforcer armed with CLAUDE_CODE_SESSION_ID unset holds a lock whose mtime never advances, so a live lead reads stale after the 30 min lease (331d measured 76 min while alive) and could be reclaimed; the record hook must refresh the lock for the derived key, and doctor must flag dead-session locks (324, 325, 321, 322 at 3170+ min); found by 331 on 2026-09-05]]
