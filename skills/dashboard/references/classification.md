# How Classification Works (Deterministic)

The script (`dashboard.rb`) computes Effort/Value/Flags/Override/Caps deterministically;
the agent never re-derives them. Read this to explain or debug a quadrant assignment.

- **Effort** — small for `research`/`exploration`/`bugfix`, for already-scoped intents
  (plan/checklist exists), or a **branch id** (folgezettel depth ≥ 2, e.g. `4a`, `12b3`); big
  otherwise. A root id (a bare number) is always depth 1, so it is never demoted by this rule.
- **Value → high** when any of: explicit `value: high`; a human-authored **root** intent; or
  an intent that is a `source` of ≥1 other intent (it has spawned follow-on work). A purely
  relational `chain` entry alone is **not** a value signal (intent 68) — else low.
- **Flags** — `unblocked` only when a **future** intent has **all** its `sources` done AND at
  least one source's completion date is strictly later than the intent's own `created` date (a
  genuine wait, not a birth-time default); `in-progress` only when the savepoint ledger shows
  real post-birth activity, not just the creation stamp; `stale` only on future intents past
  the staleness threshold. All three kept low-noise by design.
- **Override** — a `value: high|low` frontmatter field always wins (pre-stamped data, never
  model judgment at render time).
- **Caps** — quadrant lists and the project board's `active`/`future` lists are capped at 8
  entries plus a trailing "+N more" line; each entry's text is truncated to 120 characters
  with a trailing ellipsis. Applies to the Markdown board only (the ASCII renderer has its own
  separate `CELL_CAP`).
