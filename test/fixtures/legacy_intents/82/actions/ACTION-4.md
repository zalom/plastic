# ACTION-4 — Report-contract `insights:` field

Implements acceptance criterion 6 (the [[74]] report contract gains an `insights:` field on the
spawn-preamble REPORT_CONTRACT and the per-role payloads in `references/agent-report-contract.md`;
role prompts instruct agents to populate it). Pure text + one Ruby-string-constant edit; depends on
the helper being named (`insight-append`) from ACTION-3.

## Where
Code worktree: `/Users/zlatko/apps/personal/plastic/.claude/worktrees/82--`
- EDIT: `scripts/spawn-preamble` — the `REPORT_CONTRACT` constant string
- EDIT: `skills/auto/references/agent-report-contract.md` — common envelope + per-role payloads
- EDIT: `agents/plastic-brainstorming.md`, `agents/plastic-executor.md`,
  `agents/plastic-planner.md`, `agents/plastic-spec-specialist.md` (and the enforcer/reviewer
  surface if it carries the contract) — instruct agents to populate `insights:`
- EDIT: `scripts/agent-report` — surface an insights line in the synthesized fallback

## What to change

### 1. `scripts/spawn-preamble` REPORT_CONTRACT constant
Extend the verbatim `REPORT_CONTRACT` string to name the `insights:` field as part of the common
envelope. Add a clause stating the report carries an `insights:` field carrying 0..N durable
nuggets ("what I discovered worth keeping"), and that background / dispatched agents MUST populate
it because the orchestrator persists each nugget on receipt (so an insight never depends on the
discovering session's file-write access). Keep the existing wording intact; this is the single
source of truth, so the doc and role prompts must echo it.

### 2. `skills/auto/references/agent-report-contract.md`
- Add `insights:` to the `## Common envelope` bullet list: "0..N durable nuggets discovered this
  turn (the most interesting residue), each one a `## Insights`-worthy line; `none` if there were
  none."
- In `## Per-role payload`, ensure each role mentions populating `insights:` (brainstorming,
  spec-specialist, planner, executor, reviewer). The executor entry already says "Insights
  appended, with the `(autonomous)` marker" — reframe it so the executor reports its insights
  in the `insights:` field too, and note that the orchestrator (or any agent that can write the
  file) persists them via the `insight-append` helper.
- Add a short paragraph: the delivery mechanism. Insights ride home in the completion report's
  `insights:` field; the orchestrator persists each via `scripts/insight-append <intent_dir>
  <text> --stage S --author A`, which formats the `{utc-iso8601} · {stage} · {author}` prefix and
  appends at the bottom of `## Insights`. This is THE fix for dropped bg/sub-agent insights.

### 3. Role prompts (`agents/plastic-*.md`)
Each role's "Carry the common envelope ... plus the <role> payload" sentence already lists the
envelope fields; add `insights` to that list (so every role is told to populate it). For the
executor, keep its existing `## Insights` append responsibility but point it at the `insight-append`
helper as the blessed write path.

### 4. `scripts/agent-report` (synthesized fallback)
Add an `Insights:` line to the synthesized report output. Keep it a PURE function of the intent dir
(no clock): read the LAST line of the intent file's `## Insights` section (or `(none)` if absent)
and emit `lines << "Insights: #{...}"`. This keeps the fallback in step with the authored contract.

## Constraints
- `scripts/spawn-preamble`'s `REPORT_CONTRACT` is the single source of truth; the doc and prompts
  reproduce it. Keep all in agreement.
- No em-dashes in the user-facing reference doc and prompts; use a hyphen. (The Ruby string
  constant is internal but keep it hyphen-clean for consistency.)
- Ruby-first for the `agent-report` edit; pure function, no wall-clock read.

## Verification
The spawn-preamble test asserts the verbatim REPORT_CONTRACT wording, so it WILL need updating:
```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/82--
# update test/spawn_preamble_test.rb's REPORT_CONTRACT assertion to match the new constant
ruby -Itest test/spawn_preamble_test.rb
ruby -Itest test/agent_report_test.rb
```
Both green. Then confirm the field is present:
`grep -n "insights" scripts/spawn-preamble skills/auto/references/agent-report-contract.md`
shows the new field. Finally `ruby bin/test` stays green.
