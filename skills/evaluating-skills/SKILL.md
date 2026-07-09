---
name: plastic-evaluating-skills
description: >
  Evaluate Plastic skills for correctness, convention compliance, and
  progressive disclosure. Use when testing whether a skill produces good
  outputs, verifying convention compliance after changes, running evals
  against skills or instructions, creating evals for a new or updated
  skill, checking if a description triggers correctly, or assessing
  whether a skill is still needed. Also use when the user says "evaluate",
  "test the skill", "run evals", "check conventions", or "write evals".
user-invocable: true
---

# Evaluating Skills

Eval methodology for Plastic skills, based on
[agentskills.io](https://agentskills.io/skill-creation/evaluating-skills)
and [Anthropic's eval guide](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents).

## Gotchas

- Assertions written before observing output are almost always wrong — run
  the eval first, observe actual output, THEN write assertions
- Near-miss negative test cases are the most valuable — prompts that share
  keywords with should-trigger cases but need a different skill entirely
- Select the best skill iteration by validation pass rate, not the last one
- Grade outcomes, not execution paths — if the agent solved the task via an
  unexpected route but produced correct output, that is a pass
- Same skill can behave differently across agent frameworks — test on each
  target agent (Claude Code, Hermes, OpenClaw, Codex)

## Procedure

### Step 1: Choose eval scope

Determine what you are evaluating:

- **Description triggering** — does the agent activate the right skill for
  a given prompt? Tests the description field effectiveness.
- **Output quality** — does the skill produce correct results when activated?
  Tests the skill body and references.
- **Convention compliance** — does the output follow Plastic conventions?
  Read `references/convention-checks.md` for the full assertion library.

Multiple scopes can apply to the same skill. Start with the scope that
addresses your immediate concern, add others as needed.

### Step 2: Design test cases

Create `evals/evals.json` in the skill being evaluated. Copy the starter
template from `assets/eval-template.json` in this skill.

**For description triggering:**
- Write ~20 queries: 8-10 should-trigger, 8-10 should-not-trigger
- Split 60/40 into train and validation sets (proportional mix in each)
- Include near-miss negatives that share keywords but need a different skill
- In `expected_output`, describe whether the skill should or should not activate
  and why

**For output quality:**
- Start with 2-3 test cases, expand after first results
- Use realistic user prompts with varied phrasing, detail level, and formality
- In `expected_output`, describe what correct output looks like — not exact text
- Use `files` array for any input files the test needs

**For convention compliance:**
- Start with 2-3 test cases targeting specific convention areas
- In `expected_output`, describe which conventions must be met
- Read `references/convention-checks.md` for the full assertion library

Leave `assertions` arrays empty. They are populated after Step 4.

### Step 3: Run paired evals

Dispatch a subagent per test case to ensure clean context — no leakage
between test runs. Run each case twice:

1. **With skill** — the skill is available and loaded
2. **Without skill** — the skill is not available (baseline comparison)

The delta between with-skill and without-skill measures what the skill adds.
If the delta is negligible, the skill may not be adding value for that case.

Grade outcomes, not paths. An unexpected tool-call sequence that produces
correct output is still a pass.

### Step 4: Write assertions after observing

Review actual outputs from Step 3. Write specific, verifiable assertions
based on what you observed — not what you expected beforehand.

Choose the grader type that fits each assertion:
- **Code-based** — structure, file existence, format validity, counts
- **LLM-as-judge** — quality, completeness, tone, semantic correctness
- **Human** — edge cases, calibration, judgment calls

Read `references/eval-methodology.md` for the full grader taxonomy and
LLM-judge calibration protocol.

Good assertions are specific, verifiable, and countable:
"Output includes at least 3 concrete recommendations."

Weak assertions are vague: "Output is good."
Brittle assertions use exact phrase matching.

Require concrete evidence for PASS. No benefit of the doubt.

### Step 5: Grade and iterate

Compute pass rates per test case and aggregate across the eval suite.

Track two metrics separately:
- **pass@k** — succeeded at least once in k trials (capability)
- **pass^k** — succeeded every time in k trials (reliability)

Read `references/eval-methodology.md` for formulas and interpretation.

Three signal sources for skill improvement:
1. **Failed assertions** — specific gaps in the skill
2. **Human feedback** — broader quality issues not captured by assertions
3. **Execution transcripts** — reveals WHY things went wrong

Feed all three plus the current SKILL.md to propose targeted changes.
Iterate on the train set only. Check the validation set for generalization.
5 iterations is usually enough. If not improving after 5, the test cases
themselves may be the problem — revisit Step 2.

### Step 6: Graduate and monitor

Once a skill hits ~100% on capability evals (pass@k = 1.0 for 3+
consecutive runs):

1. **Graduate** capability evals into regression tests — run them on every
   skill change to protect against backsliding
2. **Monitor** the with/without delta over time — if it shrinks to zero
   across 3+ runs, the model may have internalized the skill
3. **Retire** cautiously — archive the skill, do not delete. Re-test after
   model updates in case capabilities regress.

Read `references/eval-methodology.md` for graduation criteria, retirement
detection, and the three-layer eval taxonomy.
