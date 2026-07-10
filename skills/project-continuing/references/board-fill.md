# Board Fill Mechanics

Depth reference for the "Continue (present the board)" section of `SKILL.md`. The fill itself
is mechanical; `plastic-dashboard` owns the rules, this page is a pointer plus the detail that
would otherwise bloat the SKILL.md body.

## Fill rules (owned by plastic-dashboard, summarized here for convenience)

- `{{a.b.count}}` -> the integer (e.g. `counts.active` is that count).
- `{{...lines}}` -> join the list's `.line` strings with real newlines (one per line). These
  are ordinary prose lines; never add a `-` prefix, never emit `<br>`. An empty list renders
  `_(none)_`.
- `next_work.lines` -> the most-valuable next work, already ranked and capped.
- `active.lines` / `future.lines` (project board) -> one line per intent, already formatted.
- Scalars (`{{date}}`, `{{slug}}`, `{{description}}`) -> substitute verbatim.

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
