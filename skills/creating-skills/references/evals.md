# Evals (author-time gate)

This is the gate, not the method. It states the eval decisions an author makes while building a
skill, then hands the full procedure to one place. Do not duplicate that procedure here.

## Build evals before docs

Build at least three evals before writing extensive documentation. A skill without an eval is an
assertion, not a capability, so the eval forces the skill to close a real observed gap instead of an
imagined one. [F1]

Build RED-GREEN-REFACTOR. Run the scenario without the skill and record the verbatim failure (RED),
write the minimal instructions that fix exactly that failure (GREEN), then close the loopholes the
failure exposed (REFACTOR). Only instructions that move a failing eval earn their tokens. [F2]

## What each eval must cover

- Description triggering. Pair should-trigger queries with near-miss negatives: prompts that share
  keywords with the skill but need a different skill entirely. Near-miss negatives catch
  over-triggering, the most common description failure. State the trigger set here; do not size the
  query count or split here. [F3]
- Output quality. Write assertions only after observing real output. Make them specific, verifiable,
  and countable, with no benefit of the doubt and no brittle exact-phrase matching. Assertions
  written before observation encode hopes, not behavior, so include at least one output-quality case
  graded this way. [F4]
- Discipline under pressure. For a skill whose job is restraint, stack pressures (time, sunk cost,
  authority, exhaustion) with forced options and run the case via a subagent. Reciting the rule is
  not complying with it. [F5]

## Grading and reliability decisions

Grade with the cheapest sufficient tier, and track capability (pass@k) separately from reliability
(pass^k) with k at least three. The evaluating-skills skill owns the grader taxonomy, judge
calibration, clean-context execution, and cross-model testing. [F6, F7, F8]

## Run them with the methodology skill

Use the evaluating-skills skill to author and run the evals. It owns the full method: eval scope
selection, the query-count and train/validation protocol, the grader taxonomy and judge calibration,
the iteration loop, and graduation of stable capability evals into regression. It is the source of
truth for those steps; this file states the author-time gate and stops there. [F6, F7, F8]
