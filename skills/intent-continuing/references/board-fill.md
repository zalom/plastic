# Board Fill Mechanics

Depth reference for the "Continue (present the board)" section of `SKILL.md`. The fill itself
is mechanical; `plastic-dashboard` owns the rules, this page is a pointer plus the detail that
would otherwise bloat the SKILL.md body.

## Fill rules (owned by plastic-dashboard, summarized here for convenience)

- `{{a.b.count}}` -> the integer (e.g. `counts.active` is that count).
- `{{<list>.rows}}` -> the two intent lists (`active`, `next_work`) render as Markdown table
  rows. The template hard-codes each table's header and separator; the placeholder becomes one
  data row per entry, in that table's fixed column order, cells dropped verbatim from the
  payload (cells arrive pipe-escaped and whitespace-normalized; do not re-escape or
  re-truncate). Column order per table:
  - `next_work` -> `| id | what | value | disposition | flags_label |`
  - `active` -> `| id | what | stage |`
  Empty list -> one full-width row with `_(none)_` in the Id column, other cells blank, matching
  that table's column count. Neither list carries an overflow "+N more" row (intent 202): the
  true pool size rides on the payload (`active_total`/`next_total`, shown as
  `active_shown`/`next_shown`), stated in prose by `{{footer}}` instead. Never emit `<br>`.
- `{{projects.lines}}` (global board) -> the project rollup stays prose, one line per project.
- Scalars (`{{date}}`, `{{slug}}`, `{{summary}}`, `{{footer}}`) -> substitute verbatim.
  `summary` (the 2-3 sentence "what was delivered most recently") and `footer` (the
  honest-totals + how-to-see-everything line) are finished prose built in `dashboard.rb`,
  replacing the old recently-worked table and the raw future table respectively.

No re-sorting, no re-summarizing, no hand-written prose replacing a line the payload already
supplies. Same store state produces a byte-identical payload regardless of model.

## Store-health surfacing

Every board load runs the scoped `doctor --store <scope>` check server-side (inside
`dashboard.rb`, not this skill). The payload carries the result as `store_health` (`{scope,
status, summary, failing_checks}`). Render it as a single line, for example `store health:
pass (3/3)` or `store health: warn (orphaned_intents)`. A warn or fail is informational only;
it never blocks presenting the board.

## Project vs. global fallback

The project route's default target is the project board. When no project is loaded (the rare
case where this route is reached without a registered project in scope), fall back to the
global board payload (`dashboard.rb continue --data`) rather than failing. This mirrors the
router's D6 default: a bare "continue" always lands somewhere useful.

## The screen surface (intent 331d)

`dashboard.rb project <slug> --screen` (or `continue --screen`) prints the identical state -
Active, In delivery, Delivered, Roadmap, Sessions, Changed, then the Where-we-are and
Where-we-go-next tables - as a screen with its own grammar instead of a filled Markdown
template. It replaces this fill mechanism once intent 331f wires the project route to print
it first, the way the intent route already prints the intent screen first today; until then,
this page's fill rules stay the route's own surface.
