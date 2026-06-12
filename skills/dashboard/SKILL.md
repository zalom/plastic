---
name: plastic-dashboard
description: Use when the user wants an overview of intents, asks "where are we", "what's next", "what should I work on", "show the dashboard", or invokes /plastic-dashboard. Renders a deterministic Value×Effort work cockpit across the global store and all projects, and emits a machine-readable queue that auto mode consumes.
---

# Dashboard — Plastic Work Cockpit

A deterministic, template-driven overview of the intent store(s). It answers three
questions at a glance — **where we are** (active + last touched), **where we go next**
(a Value×Effort matrix), and **how to conduct it** (a disposition verb per intent) — and
emits a JSON manifest that `plastic-auto` reads to pick the next dispatchable intent.

The script does the rendering. The LLM is **never** in the rendering path: same store
state → byte-identical output, regardless of model. Do not hand-summarize intents when
this skill applies — run the script and show its output verbatim.

## When to Use

- User invokes `/plastic-dashboard`
- User asks "where are we", "what's next", "what should I work on", "show me the intents"
- `plastic-continuing` embeds the `continue` view on resume
- `plastic-auto` reads `--json` to choose the next dispatchable intent

## Procedure

### Step 1 — Run the script

```bash
ruby ~/.plastic/scripts/dashboard.rb [continue|project <slug>|all] [--json]
```

| Mode | Shows |
|------|-------|
| `continue` (default) | Cross-scope: active + last touched, then the Value×Effort matrix for all scopes |
| `project <slug>` | One project: active line + its Value×Effort matrix |
| `all` | Per-scope roll-up summary |
| `--json` | The auto-mode manifest (any mode); machine-readable, not for humans |

The script is **read-only**. Print its stdout verbatim — do not reformat, re-sort, or
re-summarize. That is what keeps the output uniform.

### Step 2 — Read the matrix

```
                 small effort          big effort
   high value    QUICK WIN             ★ NEXT BIG THING
   low value     DEFER → agent         TRIAGE / question
   (type=research/exploration → RESEARCH band, regardless of quadrant)
```

Disposition verbs: `▸ drive` (human leads), `⇢ defer` (agent knocks off),
`⊙ research` (research/explore agent), `⚑ triage` (human review / maybe abandon).
Flags: `⇡ unblocked` (a dependency just completed), `(Nd)` stale age.

### Step 3 — Act on it

- **★ Next big thing** and `▸ drive` / `⚑ triage` items → the human leads (brainstorm → plan → exec).
- `⇢ defer` and `⊙ research` items → dispatchable to agents.
- In auto mode, read `--json` and work `dispatchable_queue` in `rank` order; leave
  `human_only` for the user.

## JSON contract

```json
{ "generated_for": "auto-mode", "scope": "<scope|all>",
  "next_big_thing": "<id|null>",
  "dispatchable_queue": [ {"id","scope","disposition","type","value","effort","flags","rank"} ],
  "human_only": ["<id>", "..."] }
```

## How classification works (deterministic)

- **Effort** — small for `research`/`exploration`/`bugfix`, for already-scoped intents
  (plan/checklist exists), or deep refinement branches; big otherwise.
- **Value** — high only for an explicit `value: high` frontmatter field, or a
  human-authored root intent that has spawned follow-on work (`chain` non-empty); low otherwise.
- **Override** — a `value: high|normal|low` field in an intent's frontmatter wins. This is
  the only place model judgment enters, and only as pre-stamped data (never at render time).

## Eval

This skill's eval is **render the template**: run the engine against the test fixture
store and assert byte-identical text + JSON output against the golden snapshots in
`test/fixtures/dashboard/`. See `test/dashboard_test.rb`. If output drifts from the
golden files without an intentional template change, the skill is broken.

## Notes

- Clusters (Zettelkasten grouping in INDEX.md) are intentionally **not** rendered — they
  are orthogonal to "what to work on next."
- Glyphs are monochrome Unicode (no emoji); they render in standard terminal emulators.
- This is additive: it changes no core lifecycle, gate, or cycle logic.
