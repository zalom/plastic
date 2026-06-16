---
name: plastic-dashboard
description: Use when the user wants an overview of intents, asks "where are we", "what's next", "what should I work on", "show the dashboard", or invokes /plastic-dashboard. Renders a deterministic Value×Effort work cockpit as Markdown across the global store and all projects, and emits a machine-readable queue that auto mode consumes.
---

# Dashboard — Plastic Work Cockpit

A deterministic overview of the intent store(s). It answers three questions at a glance:
**where we are** (recently worked), **where we go next** (a Value×Effort matrix), and
**how to conduct it** (a disposition per intent). The human-facing surface is **Markdown**,
because the user's UI renders Markdown natively but collapses raw tool-call stdout.

The script does all the data work. The agent fills a Markdown template from the script's
payload with near-zero reasoning and **presents the filled board in its reply**. Same store
state → byte-identical payload, regardless of model. Do NOT hand-summarize intents.

## When to Use

- User invokes `/plastic-dashboard`
- User asks "where are we", "what's next", "what should I work on", "show me the intents"
- `plastic-continuing` lands on the board on resume
- `plastic-auto` reads `--json` to choose the next dispatchable intent

## Procedure (the Markdown board — default human surface)

### Step 1 — Get the data payload

```bash
ruby ~/.plastic/scripts/dashboard.rb [continue|project <slug>] --data
```

- `continue` (default) → the **global** board payload (`mode: "global"`).
- `project <slug>` → that **project** board payload (`mode: "project"`).

The payload is read-only JSON. Global-board fields: `date`, `recently_worked`, `matrix`
(`quick_win`/`next_big`/`defer`/`triage`/`research`, each a list of `{line, bullet, ...}`),
`counts`, `projects`, `project_totals`. Project-board fields: `slug`, `description`,
`recently_worked`, `matrix`, `counts`, `active`, `future`.

### Step 2 — Fill the matching template

Templates live in this skill's `templates/` directory:
`~/.claude/skills/plastic-dashboard/templates/dashboard-global.md` and
`dashboard-project.md`.

Fill mechanically — no rewriting, no re-sorting:
- `{{a.b.count}}` → the integer (e.g. `matrix.quick_win.count` = that list's length).
- `{{...lines}}` → join the list's `.line` strings with **real newlines** (one per line).
  These lines are already glyph-led (the glyph is the bullet — never add `-`, never emit
  `<br>`). If a matrix quadrant list is empty, render `_(none)_`.
- `projects.lines` → one line per project:
  `- **{slug}** — {description} · active {active} · done {done} · future {future} · last accessed {last_accessed_at[0,10]}`.
- Scalars (`{{date}}`, `{{slug}}`, `{{description}}`) → substitute verbatim.

### Step 3 — Present it (mandatory, every invocation)

**Paste the filled Markdown into your reply.** This is non-optional: the board only reaches
the user when it is in the chat reply, not in tool-call stdout. Never describe the board
instead of showing it.

### Step 4 — Entry flow (the board is the menu)

The board lists everything; the user navigates by free prose (no capped picker):
- On the **global** board, the user replies with an **intent id** (work it), a **project
  name** (re-run `project <slug> --data` and present that board), or **"new"** (start a new
  intent in global via `plastic-creating-intent`).
- On a **project** board, the user replies with an **intent id**, or **"global"** to return.

## Auto-mode contract (`--json`)

`plastic-auto` consumes a separate machine-readable manifest (unchanged):

```bash
ruby ~/.plastic/scripts/dashboard.rb [continue|project <slug>|all] --json
```

```json
{ "generated_for": "auto-mode", "scope": "<scope|all>",
  "next_big_thing": "<id|null>",
  "dispatchable_queue": [ {"id","scope","disposition","type","value","effort","flags","rank"} ],
  "human_only": ["<id>", "..."] }
```

Work `dispatchable_queue` in `rank` order (`defer`/`research`); leave `human_only` for the user.

## Text modes (terminal / legacy)

`dashboard.rb [continue|project <slug>|all]` with no flag still prints the ASCII cockpit for
a raw terminal. The Markdown board (`--data` + template) is the surface for the chat UI.

## How classification works (deterministic)

- **Effort** — small for `research`/`exploration`/`bugfix`, for already-scoped intents
  (plan/checklist exists), or deep refinement branches; big otherwise.
- **Value → high** when any of: explicit `value: high`; a human-authored **root** intent; an
  intent with a non-empty `chain`; or an intent that is a `source` of ≥1 other intent. Else low.
- **Flags** — `unblocked` only when a **future** intent has **all** its `sources` done;
  `stale` only on future intents past the staleness threshold. Both kept low-noise by design.
- **Override** — a `value: high|low` frontmatter field always wins (pre-stamped data, never
  model judgment at render time).

## Eval

The eval is the payload + golden snapshots: run the engine against the fixture store and
assert the `--data` payload shape/sorting/classification and the byte-identical `--json` +
text goldens in `test/fixtures/dashboard/`. See `test/dashboard_test.rb`. Drift without an
intentional change means the skill is broken.

## Notes

- Quadrant lists are **not** Markdown `-` bullets — the glyph is the bullet (the boards are
  UI-only and may evolve, so they need not be valid Markdown lists). Never emit `<br>`.
- Clusters (Zettelkasten grouping in INDEX.md) are intentionally not rendered.
- Additive: changes no core lifecycle, gate, or cycle logic.
