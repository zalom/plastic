---
name: plastic-intent-speccing
description: >
  Consolidate the enriched Why (`## Context`, `### Decisions`, `## Insights`) into `spec.md`
  through a deterministic, judgment-free numbered sequence. Use when the user types the command
  to turn the brainstorm into a spec, asks to "write the spec", "spec this intent", "consolidate
  into spec.md", or the active intent is at Why with enough Decisions on record to close it out.
  Also fires on an indirect request that never names spec.md, such as "turn what we just
  discussed into the contract the planner builds from." Distinct from `plastic-intent-brainstorming`
  (the exploration that produces the enriched Why, upstream of this skill) and
  `plastic-intent-planning` (turns an existing spec.md into plan.md for How, downstream of this
  skill).
user-invocable: true
---

# Intent Speccing

Consolidate the enriched Why into `spec.md` through eight fixed steps, one action per step. The
next action is never a judgment call: when a section cannot be filled from what is on record,
step 5 is to stop and ask, never invent.

## Precondition

Run only when the active intent is at Why (its `## Intent` and enriched `## Context` plus
`### Decisions` exist, `spec.md` does not yet exist or is being redone) and the user has asked to
consolidate that Why into the spec. If no intent is active, or the active intent is not at Why,
report that and stop; do not guess which intent is meant.

## The 8-step sequence

| Step | Action |
|---|---|
| 1 | Confirm the precondition above. |
| 2 | Read inputs in fixed order and build a ruling ledger: (a) `## Context` and `### Decisions`; (b) `## Insights` newest-last, so a later ruling supersedes an earlier conflicting one; (c) `resources/discovery--<slug>.md`; (d) any other `resources/*.md`. |
| 3 | Decide the tier: adopt the brainstorming `Tier:` recommendation from Decisions or Insights; otherwise apply the PLASTIC.md tiers rubric (S = single mechanism or file cluster, M = one subsystem, L = cross-cutting or novel design). |
| 4 | Fill the template section by section, all 8 sections in template order. Read `references/per-section-fill-rules.md` now, filling the template is the trigger. Write the tier as the literal top line above `# Spec:`. Encode every ruling into its matching section, later supersedes earlier on conflict. A collapsed single-line S/M section is complete and valid; do not pad it. |
| 5 | Gap rule: if any section cannot be filled from the ledger built in step 2, STOP and ask the user for the missing ruling. Never invent scope to fill a gap. |
| 6 | State the gate position (below) so the user knows what happens next. |
| 7 | Self-verify against the checklist. Read `references/self-verify-checklist.md` now, verifying before presenting is the trigger. Fix any failing check, then re-verify from the top. |
| 8 | Present `spec.md` for the user-review gate, then hand off to `plastic-intent-planning` for How. |

## Gate position (step 6)

The Why stage's deliverable is `spec.md`; the gate is satisfied the moment a complete, real
`spec.md` exists (this is the gates-by-name framing: gate-check enforces spec.md before plan.md,
not the Transition Gates table row). Writing `plan.md` is what opens the code gate for Exec, and
writing `plan.md` is not this skill's job, that is `plastic-intent-planning`. State this to the user
at step 6 so the handoff at step 8 is expected, not a surprise.

## Tier stamp (step 3, convention only)

Write `Tier: S|M|L` as the literal first line of the file, above the `# Spec:` heading. This line
is convention-only: the orchestrator and the planner read it, no gate and no doctor check
validates it.

## Completion report

State, in this order: which file was written (`spec.md`, new or rewritten), the stamped `Tier:`
value, the count of Acceptance Criteria produced (the surface the planner will cover), which
`## Insights` rulings superseded an earlier Decision (if any) and where each landed, and the
handoff target (`plastic-intent-planning`). If step 5 stopped for a missing ruling, report that
instead: which section, what is missing, and the question put to the user.

## References

| Trigger | Read |
|---|---|
| Filling the template (step 4) | `references/per-section-fill-rules.md` |
| Self-verifying before presenting (step 7) | `references/self-verify-checklist.md` |
