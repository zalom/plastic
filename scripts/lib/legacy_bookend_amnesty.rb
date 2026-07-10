# encoding: UTF-8
# frozen_string_literal: true

# Intent 170a - A2 cutoff amnesty for the legacy savepoint Done-bookend gap.
#
# Frozen 2026-07-10. Pre-161 terminal intents predate
# Bridge.append_terminal_savepoint, so their savepoint.md never got a
# `Done delivered|abandoned` line. This list grandfathers exactly those,
# keyed by store scope plus intent id, so doctor's signals_complete check
# stops counting them as gaps. Every intent NOT on this list still warns if
# its savepoint lacks the Done bookend, including any new terminal intent
# going forward. This is a frozen historical snapshot: it must never grow.
# Regenerating it requires re-running the exact predicate below against the
# real store and reviewing the diff, never appending ad hoc.
#
# Predicate used to build this list (2026-07-10): for each store in
# Doctor#done_signal_stores(nil), each dir in index_sections_by_dir(index),
# terminal = the dir's INDEX section is Completed or Abandoned, gap =
# savepoint.md exists AND does not match
# /\bDone\b.*\b(delivered|abandoned)\b/.
#
# This does NOT grandfather the separate outcome.md completeness gap
# (checked independently at scripts/doctor.rb:603-607); some of these ids
# may still warn on that axis.
module LegacyBookendAmnesty
  LIST = {
    "global" => %w[1a 1a2 23].freeze,
    "project:plastic" => %w[
      1 11 121a 124 128 13 13b 15 158 158a 159 160 163 1a 1b1a3 22 30a1a 34
      36a 36a1 37 38 39 45 45a 49 4a 4a1 4a1c1 50 52 54 55 56 58 59 60b 65
      66 66a 66b 66c 66c1 67 68 71 72 73b 73c 73c1 73c2 73c3 74 77 79 80 83
      84 85a 9
    ].freeze,
  }.freeze
end
