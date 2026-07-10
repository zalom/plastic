---
name: plastic-project-continuing
description: >-
  Use when the user wants to land on the project board, asks "what should I work on" in this
  project, or wants active intents plus the most-valuable next work surfaced. This is the
  default route of plastic-continuing for a bare "continue" with no specific intent or roadmap
  named. It presents state and stops without asking how to proceed - that single mode question
  lives in plastic-intent-starting, once the user names a specific intent to work.
user-invocable: true
---

# Project Continuing - land on the board

`plastic-project-continuing` is the project route of `plastic-continuing`. It lands on the
Markdown board, presents active work and the most-valuable next work, and stops. It does not
resume a specific intent by ledger (that is `plastic-intent-continuing`) and it asks nothing.

## Continue (present the board)

Land on the Markdown board via the `plastic-dashboard` skill. Rendering belongs there, not
here - run the data payload and fill + present the matching template:
- Project loaded -> `ruby ~/.plastic/scripts/dashboard.rb project <slug> --data`
- Otherwise (no project loaded, the global fallback) -> `ruby ~/.plastic/scripts/dashboard.rb continue --data`

Fill the matching template from `plastic-dashboard`'s `templates/` and **present the filled
Markdown in your reply** (every time, non-optional). If the reply does not contain the filled
Markdown, the user sees nothing - tool-call stdout and hook `additionalContext` are both
invisible to them. `hook-continue` also emits a one-line `systemMessage` summary as a
hook-owned fallback; treat it as a floor only, never as a substitute for presenting the full
board here. See `plastic-dashboard` for the fill mechanics (`references/board-fill.md` has the
scoped detail).

The board load runs the scoped store check on every load (`doctor --store <scope>`): the
global board runs `--store global` and a project board runs `--store <slug>`. The result
arrives in the payload as `store_health`; surface it as a one-line store-health note. It is
non-fatal (a warn or fail is shown as data, it does not block continuing).

## Priority Order

1. **Active intents first** - surface work in progress.
2. **Project context** - if in a registered project, show governing + tactical intents.
3. **Stale future intents** - surface for triage (see below).
4. **Fresh future intents** - offer as next work.

## Stale Future Intents

If a future intent's `created` date is older than the configured `stale_threshold_days`
(default 3), surface it for triage without taking action:

```
Stale future intents (no action taken):

- [ID - name] (X days old)
  a) Activate - start working on it now
  b) Abandon - mark as abandoned
  c) Defer to agent: implement | research | ideate
  d) Auto - go fully autonomous (invokes plastic-auto)
```

When the user activates a future intent, move it to `## Active` in INDEX.md and auto-commit.

**Defer to agent: research.** Selecting `research` is a real dispatch, not a label. Resolve
`plastic-future-intent-researcher`'s model via `read-config agents.models.<basename> --project
<repo>` (project override, then global, then the shipped tier default) rather than relying on
bare frontmatter, which also honors a sanctioned `agents.models.<name>` override if one is
configured. Dispatch the agent (Agent tool, `subagent_type: "plastic-future-intent-researcher"`)
on the selected stale future intent, passing the resolved model explicitly. The agent writes its
findings into that intent's `## Context` (see `agents/plastic-future-intent-researcher.md`); it
does not itself dispatch further sub-agents. Once it returns, re-present the stale-future-intent
triage so the user can act on the fresh findings now on record.

## Deciding rules

The board's Value x Effort quadrants are deterministic, computed by `dashboard.rb`; this skill
never re-derives them. Cite the rule NAMES only when explaining a quadrant: Effort, Value,
Flags, Override, Caps. Read `plastic-dashboard`'s `references/classification.md` for the
definitions; do not restate or copy them here.

## Then stop

Present "here is the state, what next?" and wait. Offer active intents first, then future
intents. Do not start executing work. The only follow-up from here:
- User/agent names a specific intent to continue -> hand to `plastic-intent-continuing`
  (which reads the ledger and, in turn, hands to `plastic-intent-starting` for the single
  auto-or-guided ask).

## Coordination

Intent 149 (dashboard becomes prose summaries, queued wave 3) will change the board's
rendering path. This skill is built against today's live templated Value x Effort matrix and
cites `classification.md` rule names by name, not logic, so when 149 lands its implementer
must re-check that this skill's rule-name citations and the `dashboard.rb project <slug>
--data` -> `dashboard-project.md` path still resolve.

## References

- `references/board-fill.md` - the template-fill mechanics and store-health surfacing detail.
