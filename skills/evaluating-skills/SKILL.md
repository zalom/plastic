---
name: evaluating-skills
description: >
  Evaluate Plastic skills for correctness, convention compliance, and
  progressive disclosure. Use when testing whether a skill produces good
  outputs, verifying convention compliance after changes, running evals
  against PLASTIC.md restructuring, or when the user says "evaluate",
  "test the skill", "run evals", or "check conventions".
---

# Evaluating Skills

Based on [agentskills.io/skill-creation/evaluating-skills](https://agentskills.io/skill-creation/evaluating-skills)
and [Anthropic's eval engineering guide](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents).

## Procedure

### Step 1: Design test cases

Create `evals/evals.json` with realistic prompts, expected outputs, and optional files.
Start with 2-3 test cases, expand after first results.

For each test case:
- **Prompt**: realistic user message (varied phrasing, detail, formality)
- **Expected output**: human-readable description of success
- **Assertions**: added AFTER first run (not before)

### Step 2: Run paired evals

Run each test case twice: with the skill and without (or previous version).
Each run starts with clean context (subagent or separate session).

### Step 3: Write assertions after observing output

Good assertions are specific, verifiable, and countable.
Require concrete evidence for PASS. No benefit of the doubt.

### Step 4: Grade and iterate

Three signal sources for improvement:
1. Failed assertions → specific gaps
2. Human feedback → broader quality issues
3. Execution transcripts → WHY things went wrong

### Step 5: Aggregate and compare

Compute pass rates with/without skill. The delta tells you what the skill
costs (tokens, time) vs what it buys (quality improvement).

## Convention Compliance Evals

Load `evals/evals.json` for Plastic-specific convention checks.

For full evaluation methodology detail, read `references/eval-methodology.md`.

## Gotchas

- Assertions added BEFORE seeing output are almost always wrong — observe first
- Near-miss negative test cases are most valuable (share keywords, need different thing)
- Select best iteration by validation pass rate, not last iteration
- 5 iterations usually sufficient — if not improving, the queries may be the problem
