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

The payload is read-only JSON. Global-board fields: `date`, `store_health`, `recently_worked`,
`matrix` (`quick_win`/`next_big`/`defer`/`triage`/`research`, each a list of `{line, bullet, ...}`),
`counts`, `projects`, `project_totals`. Project-board fields: `slug`, `store_health`,
`description`, `recently_worked`, `matrix`, `counts`, `active`, `future`.

Each board load runs the scoped store check (`doctor --store <scope>`): the global board runs
`--store global` and a project board runs `--store <slug>`. The result rides in the payload as
`store_health` (`{scope, status, summary, failing_checks}`). Surface it as a one-line
store-health note on the board (for example `store health: pass (3/3)` or
`store health: warn (orphaned_intents)`). It is non-fatal: a warn or fail is shown as data and
never blocks the board.

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

**Paste the filled Markdown into your reply.** This is non-optional: if the reply does not
contain the filled Markdown, the user sees nothing — tool-call stdout and hook
`additionalContext` are both invisible to them. Never describe the board instead of showing
it, and never assume a hook already showed it for you.

`hook-continue` also emits a one-line `systemMessage` summary (counts, and the next big thing
when there is one) as a hook-owned fallback, independent of the agent's reply. Treat that line
as a floor only, not a substitute for this step: it carries no matrix, no recently-worked
section, and no entry-flow prompt. Presenting the full board here remains mandatory regardless
of whether the summary line fired. This stays a soft, agent-followed mechanism — there is no
stronger enforcement for a full multi-section Markdown document in this harness today.

### Step 4 — Entry flow (the board is the menu)

QMD-first (when available): when the user navigates by describing an intent rather than giving its
id, before scanning the store with grep/Read run `ruby ~/.plastic/scripts/qmd-sync search "<terms>"`
to surface the candidate intent, then open the authoritative intent file for the hit. The command is
a no-op when QMD is absent, so fall back to the existing INDEX.md / file scan.

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

The script computes Effort/Value/Flags/Override/Caps; the agent never re-derives them.
To explain or debug a quadrant assignment, read `references/classification.md`.

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
