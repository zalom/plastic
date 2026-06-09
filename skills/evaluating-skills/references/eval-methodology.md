# Evaluation Methodology

Load when choosing a grader type, interpreting pass rate results, or deciding
whether to graduate or retire evals.

Sources: agentskills.io, Anthropic eval engineering, Tessl eval framework,
Philipp Schmid skill testing guide.

## Three-Tier Grader Taxonomy

Layer graders like a Swiss cheese model — no single tier catches everything.
Use the simplest grader that covers the assertion. Combine tiers for coverage.

### Code-Based Graders

Best for structural and mechanical checks:
- File existence and correct path
- JSON/YAML validity
- Line count, character count, token budget
- Regex pattern matching (frontmatter fields, required sections)
- Exit codes from bundled scripts

Use as the default tier. Fast, deterministic, reproducible.

### LLM-as-Judge Graders

Best for subjective quality and semantic checks:
- "Does this description convey when to use the skill?"
- "Are the gotchas concrete corrections, not general advice?"
- "Does the output address the user's actual intent?"

Calibration protocol:
1. Write a natural-language rubric (not binary pass/fail)
2. Run the judge on 10-15 cases where you already know the correct grade
3. Compare judge grades to your grades — adjust rubric until >80% agreement
4. Spot-check with human grading periodically (every 5th eval run)

Rubric template:
- PASS: [specific criteria with examples]
- PARTIAL: [what partial credit looks like]
- FAIL: [specific failure modes]

### Human Graders

Best for edge cases and final calibration:
- Novel failure modes the other tiers miss
- Calibration set for LLM judges
- Final sign-off on graduating evals to regression

Use sparingly — human grading doesn't scale. Reserve for calibration
and cases where code + LLM judges disagree.

## pass@k vs pass^k

Two metrics that diverge dramatically. Always track both.

### pass@k — Capability

"Did it succeed at least once in k trials?"

Formula: pass@k = 1 - (1 - p)^k where p = single-trial pass rate

Measures: Can the skill/agent do this at all?

Example at p=0.7, k=10: pass@k = 97.2%

Use when: evaluating whether a skill enables a new capability,
initial development, deciding whether to invest more iteration.

### pass^k — Reliability

"Did it succeed every time in k trials?"

Formula: pass^k = p^k

Measures: Will it always do this correctly?

Example at p=0.7, k=10: pass^k = 2.8%

Use when: evaluating production readiness, regression testing,
deciding whether a skill is reliable enough to ship.

### Interpreting the Gap

| pass@k | pass^k | Interpretation |
|--------|--------|----------------|
| High | High | Reliable — ready for production |
| High | Low | Capable but flaky — needs iteration on consistency |
| Low | Low | Not yet capable — needs fundamental skill improvement |
| Low | High | Impossible (pass^k <= pass@k always) |

Run k=3 minimum for meaningful results. k=5 for production decisions.

## Capability-to-Regression Graduation

Track pass rates across iterations. When a capability eval consistently
hits ~100% (pass@k=1.0 for 3+ consecutive runs):

1. Graduate the eval from "capability" to "regression"
2. Regression evals run on every skill change — they protect against backsliding
3. If a regression eval starts failing, the recent change broke something
4. Investigate the failing regression before iterating further

Graduation is one-way. Once an eval is regression, it stays regression
unless the underlying requirement changes.

## Skill Retirement Detection

Monitor the with/without skill delta over time:

1. Run paired evals (with-skill vs without-skill) periodically
2. Compute the delta in pass rates
3. If delta shrinks to near-zero across 3+ consecutive runs:
   - The model has likely internalized the skill's knowledge
   - The skill may be ready for retirement
4. Before retiring: run one final full eval suite to confirm
5. Archive the skill (don't delete — may need to restore if model changes)

Common cause of false retirement signals: model update changed capabilities.
Re-test after model updates.

## Tessl Three-Layer Eval Taxonomy

Three layers of increasing realism. Each catches failures the others miss.

### Layer 1: Skill Review (Structural Lint)

Does the skill itself follow best practices?
- SKILL.md structure (frontmatter, sections, length)
- Description quality (imperative, user-intent, trigger keywords)
- Reference organization (conditional triggers, one level deep)
- Convention compliance (for Plastic skills, see convention-checks.md)

Fast, cheap, runs without executing the skill.

### Layer 2: Task Evals (Synthetic)

Does the skill improve agent output on synthetic tasks?
- Paired with/without comparison
- Controlled prompts with known-good expected outputs
- Measures the delta the skill adds

This is the core eval loop (Steps 2-5 in the SKILL.md procedure).

### Layer 3: Repo Evals (Real Codebase)

Does the skill work correctly in a real project context?
- Install the skill in a real repository
- Run real tasks (not synthetic prompts)
- Measure whether the agent uses the skill correctly in situ

Most expensive, most realistic. Catches skills that pass synthetic tests
but fail under real project complexity. Use for high-stakes skills
or before shipping to users.
