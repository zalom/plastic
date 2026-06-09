# agentskills.io Full Reference

Source: https://agentskills.io (all sections, verified June 2026)

## Specification Details

### Frontmatter Fields

| Field | Required | Constraints |
|-------|----------|-------------|
| name | Yes | 1-64 chars. Lowercase alphanumeric + hyphens. No leading/trailing/consecutive hyphens. Must match directory name. |
| description | Yes | 1-1024 chars. Non-empty. What + when. |
| license | No | Short — name or filename reference |
| compatibility | No | 1-500 chars. Environment requirements only when needed. |
| metadata | No | String→string map. Use unique key names. |
| allowed-tools | No | Space-separated. Experimental. |

### Progressive Disclosure Token Budgets

- Discovery: ~100 tokens per skill (name + description only)
- Activation: <5000 tokens / <500 lines recommended for SKILL.md body
- Execution: Unbounded — files in scripts/, references/, assets/ load as needed

### File References

- Use relative paths from skill root
- Keep one level deep from SKILL.md
- Agent resolves paths automatically

## Description Optimization

### Evaluation Methodology

1. Create ~20 eval queries (8-10 should-trigger, 8-10 should-not)
2. Split 60/40 train/validation (proportional mix in each)
3. Run each query 3 times, compute trigger rate
4. Pass threshold: 0.5
5. Near-miss negatives are most valuable (share keywords, need different thing)
6. Iterate on train set only, validate on held-out set
7. Select best by validation pass rate, not last iteration
8. 5 iterations usually sufficient

### Description Anti-patterns

- "Helps with PDFs" — too vague, no trigger context
- "Process CSV files" — no when/why, no user-intent focus
- Implementation details instead of user intent
- Missing edge case triggers (user doesn't name the domain)

## Instruction Best Practices

### Gotchas — Highest-Value Content

Concrete corrections, not general advice:

```markdown
## Gotchas
- The `users` table uses soft deletes. Queries must include
  `WHERE deleted_at IS NULL`.
- User ID is `user_id` in DB, `uid` in auth, `accountId` in billing.
  All three refer to the same value.
- The `/health` endpoint returns 200 even if DB is down. Use `/ready`.
```

### Calibrating Control

Prescriptive when:
- Operations are fragile
- Consistency matters
- Specific sequence must be followed

Flexible when:
- Multiple approaches are valid
- Task tolerates variation
- Explaining WHY is more effective than rigid rules

### Instruction Patterns

1. **Validation loops**: Do work → validate → fix → repeat
2. **Plan-validate-execute**: Create plan → validate vs source of truth → execute
3. **Checklists**: Track progress, enforce dependencies, validation gates
4. **Bundled scripts**: If agent reinvents same logic each run, bundle it
5. **Templates**: Concrete output structures > prose descriptions

## Script Design

### Hard Requirements
- No interactive prompts (hard requirement — agents hang indefinitely)
- All input via flags, env vars, or stdin

### Agent-Friendly Design
- --help as primary interface documentation
- Helpful error messages: what wrong + what expected + what to try
- Structured output (JSON/CSV/TSV), data on stdout, diagnostics on stderr
- Idempotent operations (agents may retry)
- Dry-run for destructive operations
- Meaningful exit codes documented in --help
- Output size control: default to summaries, support --offset pagination
- Agent harnesses truncate at 10-30K characters

## Evaluation Framework

### Test Case Structure
```json
{
  "skill_name": "name",
  "evals": [{
    "id": 1,
    "prompt": "realistic user message",
    "expected_output": "what success looks like",
    "files": ["evals/files/input.csv"],
    "assertions": ["specific, verifiable checks"]
  }]
}
```

### Running Evals
- With-skill vs without-skill (or previous version) comparison
- Clean context per run (subagents or separate sessions)
- Capture timing: total_tokens, duration_ms
- Start with 2-3 test cases, expand after first results

### Assertion Quality
Good: Programmatically verifiable, specific, countable
Weak: Vague ("the output is good")
Brittle: Exact phrase matching

Principle: Require concrete evidence for PASS. No benefit of the doubt.

### Iteration Loop
1. Run evals → grade assertions → aggregate benchmarks
2. Identify failures (assertions, human feedback, execution transcripts)
3. Feed all three + SKILL.md to LLM for proposed changes
4. Apply changes → re-run → compare
5. Stop when consistently empty feedback or no meaningful improvement
