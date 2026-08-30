# Deterministic cycle-step ledger, written automatically by the record hook.
# One line per lifecycle milestone, append-only, newest at the bottom:
#
#   {UTC-iso8601}  {Stage}  {milestone}
#
# Example:
#   2026-06-16T14:02:00Z  What  ID--slug.md
#   2026-06-16T14:20:00Z  Why   spec.md created
#   2026-06-16T15:10:00Z  How   plan.md created
#   2026-06-16T15:11:00Z  How   checklist.md created
#   2026-06-16T16:40:00Z  Exec  outcome.md created
#
# This file is sugar on top of the conventions, not a source of truth. It is
# rebuildable from files-on-disk via Bridge.rebuild_savepoint. Do not hand-edit.
