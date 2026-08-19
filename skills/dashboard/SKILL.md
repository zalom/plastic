---
name: plastic-dashboard
description: Use when the user wants an overview of intents, asks "where are we", "what's next", "what should I work on", "show the dashboard", or invokes /plastic-dashboard. Renders the intent store(s) as Markdown prose, the global board as a narrative of work done, each project board as a short summary plus its most-valuable next work, and emits a machine-readable queue that auto mode consumes.
user-invocable: false
---

# Dashboard — Plastic Work Cockpit

A deterministic overview of the intent store(s). It answers three questions at a glance:
**where we are** (recently worked), **where we go next** (the most-valuable next work), and
**how to conduct it** (a disposition per intent). The human-facing surface is **Markdown**,
because the user's UI renders Markdown natively but collapses raw tool-call stdout.

The script does all the data work. The agent fills a Markdown template from the script's
payload with near-zero reasoning and **presents the filled board in its reply**. Same store
state → byte-identical payload, regardless of model. Do NOT hand-summarize intents.

## When to Use

- User invokes `/plastic-dashboard`
- User asks "where are we", "what's next", "what should I work on", "show me the intents"
- `plastic-project-continuing` lands on the board on resume
- `plastic-auto` reads `--json` to choose the next dispatchable intent

## Procedure (the Markdown board — default human surface)

### Step 1 — Get the data payload

```bash
ruby ~/.plastic/scripts/dashboard.rb [continue|project <slug>] --data
```

- `continue` (default) → the **global** board payload (`mode: "global"`).
- `project <slug>` → that **project** board payload (`mode: "project"`).

The payload is read-only JSON. Global-board fields: `date`, `store_health`, `summary`,
`next_work`, `next_total`, `next_shown`, `counts`, `projects`, `project_totals`, `footer`.
Project-board fields: `slug`, `store_health`, `description`, `summary`, `counts`, `active`,
`active_total`, `active_shown`, `next_work`, `next_total`, `next_shown`, `footer`. `summary`
and `footer` are finished prose strings (2-3 sentences and one line respectively), built in
`dashboard.rb` and substituted verbatim, exactly like `{{date}}`/`{{description}}` already
are - never re-worded or re-derived by the skill. Each list carries cell-ready fields for
its table: `next_work` rows are
`{id, intent, scope, lifecycle, value, disposition, flags, what, flags_label, line}`;
`active` rows carry
`{id, intent, created, bullet, scope, what, stage, worker, activity, line}`. The `what`,
`scope`, `worker`, `activity`, and `flags_label` cell fields arrive pipe-escaped and
whitespace-normalized.

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

Fill mechanically, no rewriting, no re-sorting:
- `{{a.b.count}}` → the integer (e.g. `counts.active` = that count).
- `{{<list>.rows}}` → the two intent lists (`active`, `next_work`) render as **Markdown table
  rows**. The template hard-codes each table's header and separator; this placeholder becomes
  one data row per list entry, joined with real newlines, in that table's fixed column order
  (below). Drop each cell from the named payload field **verbatim**: cells arrive pre-escaped
  and whitespace-normalized from the script (pipes escaped as `\|`), so never re-escape,
  re-truncate, or reword them. Never emit `<br>`.
  - `next_work` → `| {id} | {what} | {value} | {disposition} | {flags_label} |`
  - `active` → `| {id} | {what} | {stage} | {worker} | {activity} |`
  Empty list → one full-width row with `_(none)_` in the Id column and every other cell blank,
  matching that table's column count (e.g. `| _(none)_ | | | | |` for the 5-column next_work
  table, `| _(none)_ | | | |` for the 5-column active table). Neither list carries an overflow
  "+N more" row anymore (D5, intent 202): the true pool size rides on the payload as
  `active_total`/`next_total` (shown counts as `active_shown`/`next_shown`), and `{{footer}}`
  states it in prose instead.
- `{{projects.lines}}` (global board only) → the project rollup stays **prose**, one line per
  project (not a table):
  `- **{slug}**: {description}, active {active}, done {done}, future {future}, last accessed {last_accessed_at[0,10]}`.
- Scalars (`{{date}}`, `{{slug}}`, `{{summary}}`, `{{footer}}`) → substitute verbatim. `summary`
  and `footer` are finished prose built in `dashboard.rb`; do not rewrite, shorten, or
  re-derive them from the counts - that is exactly the non-determinism D5 rules out.

### Paging (conversational, D4)

The board shows a short page by default (Active capped at 3, Next-work at 5). When the
user asks for "more" or "all", re-invoke Step 1 with an explicit flag and re-fill the
template with the new payload - nothing is persisted to disk, the offset lives only in the
chat turn:
- "all" → add `--all` (lifts both caps to unbounded; the footer then shows equal shown/total).
- "more" → add `--limit-active N`/`--limit-next N` with a larger `N` for whichever list the
  user is paging.

For a real, own-terminal pager instead, point the owner at `--plain`:
`ruby ~/.plastic/scripts/dashboard.rb project <slug> --plain | less` (or `continue --plain`
for the global board). `--plain` prints the full, uncapped board as plain text with no
Markdown table syntax; it is a separate CLI mode from `--data`, not something this skill
fills a template from.

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
  intent in global via `plastic-intent-creating`).
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
To explain or debug a ranking or disposition, read `references/classification.md`.

## Eval

The eval is the payload + golden snapshots: run the engine against the fixture store and
assert the `--data` payload shape/sorting/classification and the byte-identical `--json` +
text goldens in [`test/fixtures/dashboard/`](https://github.com/zalom/plastic/tree/main/test/fixtures/dashboard). See [`dashboard_test.rb`](https://github.com/zalom/plastic/blob/main/test/dashboard_test.rb). Drift without an
intentional change means the skill is broken.

## Notes

- The two intent lists (active, next work) render as Markdown tables; the prose summary,
  footer, counts, and the project rollup stay prose (intent 202). No Value x Effort grid
  returns. Never emit `<br>`.
- Clusters (Zettelkasten grouping in INDEX.md) are intentionally not rendered.
- Additive: changes no core lifecycle, gate, or cycle logic.
