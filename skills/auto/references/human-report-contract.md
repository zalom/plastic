# Human Report Contract (per-stage EM-to-CTO briefing)

This doc defines how the orchestrator briefs the human at each of the five stage boundaries
(What, Why, How, Exec, Done) in auto mode. It is the outward, human-facing counterpart to the
internal report contract in `references/agent-report-contract.md`. Voice: an engineering
manager briefing a CTO. Lead with impact, name the risk, leave the decision.

## The skeleton

One fixed 3-line shape, reused at every stage:

1. **State**: what happened and what it means, impact first, one line.
2. **Risk**: the one thing that could bite, or "nothing flagged."
3. **Call**: the decision left to you, or the go-ahead I am taking.

This is a shape, not a rigid template. Keep the order (State, then Risk, then Call) and keep it
short. The words can flex to fit the stage.

## Per-stage content

- **What**: State = the work I picked up and why it matters now. Risk = scope uncertainty.
  Call = confirm this is worth doing, or I proceed.
- **Why**: State = the approach I chose, one line. Risk = the main trade-off. Call = the one
  decision I need (approve, or pick an option).
- **How**: State = the plan shape (task count and what it builds). Risk = the riskiest task or
  dependency. Call = approve the plan to build.
- **Exec**: State = what got built and the test result. Risk = residual failures or deviations.
  Call = go to review, or done.
- **Done**: State = the delivered impact. Risk = residual risk. Call = the decision left to you
  (merge, release, accept).

## Boundary vs intent 74

Intent 74's report contract (`references/agent-report-contract.md`) is the INTERNAL,
machine-checked handoff from a dispatched specialist back to the orchestrator: a structured
envelope plus a per-role payload. This contract is the OUTWARD human briefing, orchestrator to
user, in prose. Different direction, different audience, different form. The orchestrator
CONSUMES the intent 74 report to WRITE the human briefing defined here. The two never merge.

## Brevity: point, don't repeat

Surface rules (no em-dashes, plain words, no filler openers, and so on) are owned by the
shipped `plastic-humanizer` skill and the always-on plain-language layer. This contract does not
re-list that catalog. It restates only the hard bans as one line: no em-dashes, no "not X but Y",
no rule of three, no hype words, no sycophancy, no over-bolding. Apply `plastic-humanizer` and the
always-on layer for everything else.

## Emission: guided vs auto

In guided mode, the briefing lands at each stage boundary and the human acts on the Call line
before the next stage starts.

In auto mode, the orchestrator still emits the briefing at each boundary, as a running EM-to-CTO
account. The Call line becomes the go-ahead the orchestrator takes itself and moves on, except at
the existing hard stops (destructive action without a safe alternative, project-path confirm).
