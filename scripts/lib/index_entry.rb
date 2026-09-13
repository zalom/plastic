# encoding: UTF-8
# frozen_string_literal: true

# IndexEntry - the shared INDEX.md entry matcher and Active check (intent 188,
# D12/D13; moved off the retired shared-helpers module by intent 344, D2).
#
# ONE definition site for the "- [ID <sep> Title](link)" shape both `active?`
# (below) and `scripts/end-intent`'s own INDEX-move parser depend on, so the
# two regexes can never drift apart. Accepts a real em dash (U+2014) OR a
# plain hyphen as the id/title separator on READ; every WRITE still emits the
# real em dash (D10). The separator is built from the codepoint, not a
# literal byte, so this file stays em-dash free.
module IndexEntry
  module_function

  EM_DASH = "\u2014".freeze
  ENTRY_RE = /\A- \[(\S+)\s+(?:#{Regexp.escape(EM_DASH)}|-)\s+(.*?)\]\(([^)]+)\)/.freeze

  # Match `line` (already chomped) against the shared INDEX entry shape.
  # Returns a MatchData (captures: 1 = id, 2 = title, 3 = link) or nil.
  def match(line)
    line.to_s.match(ENTRY_RE)
  end

  # True iff the intent is Active in its store's INDEX.md, which lives at the
  # PARENT of the store/ dir. Non-raising: any failure (missing or unreadable
  # INDEX, bad arg) returns false. `index_active_ids` is a pure-data test
  # seam: when an Array of id strings is supplied, membership is checked
  # against it directly with no file read.
  def active?(intent_id, store:, index_active_ids: nil)
    target = intent_id.to_s
    return index_active_ids.include?(target) if index_active_ids.is_a?(Array)

    index = File.join(File.dirname(store.to_s), "INDEX.md")
    return false unless File.exist?(index)

    in_active = false
    File.foreach(index) do |line|
      stripped = line.chomp
      if stripped == "## Active"
        in_active = true
        next
      end
      next unless in_active
      break if stripped.start_with?("## ") # next section ends the Active block
      m = match(stripped)
      return true if m && m[1] == target
    end
    false
  rescue StandardError
    false
  end
end
