# Human Report Contract (per-stage EM-to-CTO briefing)

This doc defines how the orchestrator briefs the human at each of the five stage boundaries
(What, Why, How, Exec, Done) in auto mode, at M and L; at S only the How boundary fires (see
`## Depth at Tier S`). It is the outward, human-facing counterpart to the
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

## Depth at Tier S

At Tier S in auto mode the mid-flight briefings collapse to one. Only the How briefing fires, and
it folds in what the What and Why briefings would have said: the work picked up and the approach
chosen go into its State line. The Exec briefing folds into the final owner report at End. M and L
send all four. The shape does not change: still State, then Risk, then Call, and the per-stage
content above still says what each line covers. This is a depth cut, not a new report. A delivery
still ends with `outcome.md` plus one owner report.

## One report per audience

A delivery produces exactly two artifacts: `outcome.md` (authored by `plastic-intent-ending`)
and one EM-to-CTO owner report at the End stage. No stage or skill restates a delivery
already written to `outcome.md`; point at it instead. Skills do not open with a banner that
names the skill or restates the intent id and name the owner just typed. Announce only what
the reader cannot already know: an error, a result, a choice with its reason, or a handoff.

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

In auto mode, at M and L the orchestrator still emits the briefing at each boundary, as a running
EM-to-CTO account. At S only the How briefing fires; see `## Depth at Tier S` above for what it
folds in. The Call line becomes the go-ahead the orchestrator takes itself and moves on, except at
the existing hard stops (destructive action without a safe alternative, project-path confirm).
