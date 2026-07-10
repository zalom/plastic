# encoding: UTF-8
# frozen_string_literal: true

# Renders a one-line dashboard summary for the hook-owned systemMessage floor
# (intent 125, Task 6). Pure and dependency-injected, mirroring BootBanner: it
# takes the already-parsed `dashboard.rb continue --data` JSON payload and
# returns a single line, with no file I/O and no subprocess calls in here, so
# it is unit-testable in isolation while the hook feeds it real data.
module DashboardBanner
  module_function

  # payload: the Hash from JSON.parse(`dashboard.rb continue --data`), or nil
  #          when the subprocess call failed or produced unusable JSON.
  #
  # Returns a single summary line, or nil when the payload has nothing usable
  # (the caller degrades silently in that case, omitting systemMessage).
  def render(payload)
    return nil unless payload.is_a?(Hash)
    counts = payload["counts"]
    return nil unless counts.is_a?(Hash)
    active = counts["active"].to_i
    future = counts["future"].to_i
    line = "Plastic: #{active} active · #{future} next · say \"show the dashboard\" to see the board"
    nbt = next_big_thing_id(payload)
    line += " · next big thing: #{nbt}" if nbt
    line
  end

  # The id of the top-ranked "drive" candidate, when the payload's next_work list
  # carries the shape dashboard.rb emits (an Array of {id, disposition, ...}
  # hashes, already rank-sorted). Returns nil for any other shape rather than
  # raising.
  def next_big_thing_id(payload)
    list = payload["next_work"]
    return nil unless list.is_a?(Array)
    top = list.find { |entry| entry.is_a?(Hash) && entry["disposition"] == "drive" }
    return nil unless top
    id = top["id"].to_s
    id.empty? ? nil : id
  end
end
