# Tiers — Extended Walkthrough

This is the detail behind `## Tiers` in SKILL.md. The five points there (sizing rule, two
levers, per-tier topology, never-cut list, tier record) are the authoritative contract;
this file only expands on them with examples and rationale.

## Why sizing exists

Auto mode used to run every intent through the same full-ceremony team: brainstorming,
spec-specialist, planner, executor, and an independent reviewer, each a separate agent
booting a fresh context. For a large or novel intent that ceremony earns its cost. For a
small intent (one file, one mechanism, an hour of real work) the ceremony dominates:
overhead runs about 3 to 4 times the actual work time, roughly flat regardless of size, so
it hurts small intents the most. Sizing at Why and matching the topology to that size drops
small-intent ceremony toward about 1.5x work time, without touching structure, gates, or
the savepoint ledger.

## Sizing rule, worked examples

- S: fixing one script's argument parsing, adding one skill section, a single bug fix
  confined to one file. Hours of work.
- M: adding a new agent role file end to end, a subsystem with a handful of touched files
  and one clear seam. About a day.
- L: cross-cutting prose or code that spans the skill contract plus multiple agent role
  files (like this intent, 130), or any genuinely novel design with no established pattern
  to follow.

## S/M collapsed topology, in detail

One thinker agent boots ONCE and stays in a single context for two stations:

1. Station 1 — writes `spec.md` (collapsed sections allowed, one line each is valid).
2. Station 2 — writes `plan.md` + `checklist.md` + at least one real action file in the
   SAME context (no reboot). At S/M the thinker consolidates the whole delivery into one
   `actions/ACTION_1.md` (rather than one file per task); `actions/` is populated at every
   tier, and a `.gitkeep`-only or empty `actions/` fails the How gate.

Then a sonnet executor (a fresh dispatch, this is the one topology split that always
happens) implements from plan.md + checklist.md, checks off items, appends `## Insights`,
and drives the suite green. At S/M that is ONE executor dispatch for the whole consolidated
action: no per-task implementer, and no per-task spec review or quality review. L keeps the
per-task loop. The gate lives in `plastic-intent-executing`'s Subagent-Driven workflow,
which reads the `Tier:` line stamped at the top of spec.md, the authoritative record. The
arithmetic: an S plan with N tasks costs 3N plus 1 agent boots under the L shape, and 2
boots under this one.

The independent reviewer still runs at the final gate for S/M, in its own fresh context,
never the maker. This is on the never-cut list; it does not collapse.

S sends ONE mid-flight owner briefing instead of four. Only the How briefing fires, at the
point the plan is ready and before any code is written, and it folds in what the What and
Why briefings would have said; the Exec briefing folds into the final owner report at End.
M and L send all four. The briefing calls live in `plastic-auto`'s stage sections, and the
depth note lives in `references/human-report-contract.md`.

S may skip the QMD discovery deposit (normally a `plastic-intent-discovery` pass before
Why) when the intent's `chain` and `sources` are both empty in frontmatter. With no graph
edges there is nothing to discover, so the deposit is pure overhead; a one-line context
note ("no chain/sources, discovery skipped") takes its place, written to
`resources/discovery--<slug>.md`. Three places implement the skip: the dispatch site in
`plastic-intent-starting` step 4, the precondition in `plastic-intent-discovering`, and the
same precondition in the `plastic-intent-discovery` agent file. The skip needs a size already
on record (a stamped `Tier: S` line in spec.md), and sizing happens at Why, so a first
activation usually runs the full pass.

## L topology, unchanged

L keeps today's full multi-agent team as described in `## Team Spin-Up`: brainstorming,
spec-specialist, planner, executor, each a separate agent in its own fresh context, plus
the independent reviewer at the final gate. Cross-cutting or novel work benefits from the
separate perspectives and the handoff discipline; the ceremony is not waste at this size.

## Same-structure invariant, why it is non-negotiable

The file set, stage order, gates, and savepoint ledger never change by tier. Renaming or
skipping files to save time would require new gate logic per tier and would break state
derivability (the gates and the savepoint rebuild depend on a fixed file set at fixed
paths). So the only two levers are content depth and agent topology; structure is the
constant that keeps every tier auditable the same way.

## Tier record, mechanics

The tier is recorded as a `Tier: S|M|L` line at the very top of spec.md, above the `#
Spec:` heading. It is convention-only: the orchestrator reads it to pick topology, and
nothing else depends on it. No frontmatter schema change, no new file, no doctor rule, no
gate check. If a later intent wants doctor or a gate to validate the line, that is a
separate, explicit follow-up; this system deliberately adds no new operational surface.

## Never-cut list, the safety floor

At any tier or mode: the independent reviewer (separate agent, fresh context, never the
maker), `outcome.md` as the truth of delivery, the delivery lock, worktree isolation,
intent creation via skill, INDEX as status truth, the QMD reindex at End. These are
predictability and safety guarantees, not ceremony, and lightness never touches them.
