# encoding: UTF-8
# frozen_string_literal: true

require "time"
require "fileutils"

# RoadmapSavepoint - the roadmap's machine counterpart to its human `## Log` (intent 134).
#
# Mirrors scripts/lib/qmd_sync.rb's class shape and the cycle-step savepoint ledger in
# scripts/lib/bridge.rb (append semantics: idempotent `(event, detail)` pair dedup, one
# deterministic append primitive). Constructor-DI, hermetic: no eval, no ENV or global config
# seam, clock injected through `now:`. Two operations:
#
#   append(roadmap_path, event, detail, now:)  - one deterministic, idempotent append
#   rebuild(roadmap_path)                       - reconstruct the ledger from the roadmap's
#                                                  `## Log` (and, for delivered wave entries with
#                                                  no matching Log line, from INDEX `## Completed`)
#
# The ledger is sugar on top of the roadmap file: derived, rebuildable, never a status source.
# INDEX.md stays the single status writer.
module RoadmapSavepoint
  module_function

  EVENTS = %w[created dispatched parked merged release handoff closed added reordered wave].freeze

  # Keyword -> event classification for `rebuild`, checked top to bottom, first match wins.
  # Kept small and deterministic (action 1). Order matters: more specific/rarer words are
  # checked before the broader "wave" fallback so an incidental "wave" mention in an otherwise
  # classifiable line never shadows its real event.
  KEYWORD_TABLE = [
    [/\bclosed\b/i, "closed"],
    [/\bhanded off\b|\bhandoff\b/i, "handoff"],
    [/\breleased?\b|\bcut\b|\btagged\b/i, "release"],
    [/\bparked\b|\bblocked\b|\bholds?\b/i, "parked"],
    [/\bdelivered\b|\bmerged\b|\bshipped\b/i, "merged"],
    [/\bdelivering\b|\bdispatch(?:ed)?\b/i, "dispatched"],
    [/\breordered\b/i, "reordered"],
    [/\badded\b|\badds\b/i, "added"],
    [/\bcreated\b/i, "created"],
    [/\bwave\b/i, "wave"],
  ].freeze

  # --- append -----------------------------------------------------------------

  # The name-paired sibling ledger for a roadmap path: roadmaps/<slug>.md becomes
  # roadmaps/<slug>.savepoint.md. Resolves correctly for a live roadmap and for one already
  # moved under roadmaps/archived/, because both are plain path substitutions.
  def ledger_path_for(roadmap_path)
    roadmap_path.sub(/\.md\z/, ".savepoint.md")
  end

  # `(event, detail)` pairs already recorded in a ledger file, the dedup key (D2): two
  # `dispatched` events with different details are distinct, so the event word alone would be
  # too coarse a key.
  def recorded_pairs(ledger_path)
    return [] unless File.exist?(ledger_path)
    File.read(ledger_path).each_line.filter_map { |line| parse_pair(line) }
  end

  def parse_pair(line)
    parts = line.strip.split(/\s{2,}/)
    parts.length >= 3 ? [parts[1], parts[2]] : nil
  end
  private_class_method :parse_pair

  # Append one ledger line "<iso8601>  <event>  <detail>" unless `(event, detail)` is already
  # recorded (no-op). Creates the paired ledger file (and its directory) lazily. Raises
  # ArgumentError when `event` is outside the controlled vocabulary. Returns true when a line
  # was written, false on a dedup no-op.
  def append(roadmap_path, event, detail, now: Time.now)
    unless EVENTS.include?(event)
      raise ArgumentError, "event must be one of #{EVENTS.join(', ')}, got #{event.inspect}"
    end

    ledger_path = ledger_path_for(roadmap_path)
    return false if recorded_pairs(ledger_path).include?([event, detail])

    FileUtils.mkdir_p(File.dirname(ledger_path))
    File.open(ledger_path, "a") { |io| io.write(format_line(now, event, detail)) }
    true
  end

  def format_line(time, event, detail)
    "#{time.utc.iso8601}  #{event}  #{detail.to_s.strip}\n"
  end
  private_class_method :format_line

  # --- rebuild ------------------------------------------------------------------

  # Reconstruct the paired ledger deterministically from the roadmap file's `## Log` (never the
  # roadmap `.md`, which is read-only here), cross-checked against `## Waves` and the tier's
  # INDEX so every `delivered` wave entry has a `merged` line. Every timestamp comes from an
  # on-disk source (the Log, or INDEX `## Completed`); an entry with no recoverable timestamp is
  # not emitted (D4, never invented). Overwrites the ledger (the one operation allowed to rewrite
  # it, matching `Bridge.rebuild_savepoint`). Returns the number of lines written.
  def rebuild(roadmap_path)
    text = File.read(roadmap_path)
    log_lines = classify_log(section_body(text, "Log"))
    delivered_ids = delivered_wave_ids(section_body(text, "Waves"))
    backfilled = backfill_merged_lines(log_lines, delivered_ids, roadmap_path)

    lines = dedup_pairs(log_lines + backfilled)
    File.write(ledger_path_for(roadmap_path), lines.map { |t, e, d| format_line(t, e, d) }.join)
    lines.length
  end

  # Every `- YYYY-MM-DD HH:MM UTC ...` line in the `## Log` body, classified into
  # [time, event, detail]. A line with no keyword match is dropped (no event to record); a
  # continuation line (no date prefix) never matches the header pattern, so it is inherently
  # ignored for classification, per action 1.
  def classify_log(log_body)
    log_body.each_line.filter_map { |line| classify_log_line(line) }
  end
  private_class_method :classify_log

  LOG_LINE = /\A-\s+(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})\s+UTC\s+(.*)\z/.freeze

  def classify_log_line(line)
    m = line.strip.match(LOG_LINE)
    return nil unless m
    event = classify_event(m[3])
    return nil unless event
    [parse_log_time(m[1], m[2]), event, m[3].strip]
  end
  private_class_method :classify_log_line

  def parse_log_time(date, hhmm)
    y, mo, d = date.split("-").map(&:to_i)
    h, mi = hhmm.split(":").map(&:to_i)
    Time.utc(y, mo, d, h, mi, 0)
  end
  private_class_method :parse_log_time

  def classify_event(text)
    hit = KEYWORD_TABLE.find { |regex, _event| text =~ regex }
    hit && hit[1]
  end
  private_class_method :classify_event

  WAVE_ENTRY = /\A-\s*\[([ xX])\]\s+(\S+)\s+.+—\s*(\S+)\s*\z/.freeze

  # Intent ids of every `[x] ... — delivered` entry in the `## Waves` body.
  def delivered_wave_ids(waves_body)
    waves_body.each_line.filter_map do |line|
      m = line.strip.match(WAVE_ENTRY)
      next nil unless m
      checked = m[1].strip.downcase == "x"
      status = m[3].strip.downcase
      m[2] if checked && status == "delivered"
    end
  end
  private_class_method :delivered_wave_ids

  # For every delivered wave id with no `merged` line already among `log_lines` (the "matching
  # Log line" source, D4), fall back to the tier's INDEX `## Completed` section (the second
  # on-disk source D4 allows). No source at all -> the id is silently skipped, never invented.
  # Backfilled lines are appended after the Log-derived pass (a reconciliation pass run after
  # reconstruction), each carrying its own real on-disk-sourced timestamp even when that
  # timestamp sorts earlier than same-day Log lines above it (INDEX only carries a date, so the
  # time floors to midnight UTC rather than inventing a time-of-day).
  def backfill_merged_lines(log_lines, delivered_ids, roadmap_path)
    index_path = index_path_for(roadmap_path)
    delivered_ids.filter_map do |id|
      next nil if log_lines.any? { |_t, event, detail| event == "merged" && detail =~ /\b#{Regexp.escape(id)}\b/ }
      date = index_completed_date(index_path, id)
      next nil unless date
      [Time.utc(*date.split("-").map(&:to_i)), "merged", "#{id} (from INDEX Completed)"]
    end
  end
  private_class_method :backfill_merged_lines

  # The tier root is the parent of `roadmaps/` (a live roadmap's grandparent, or, for one
  # already moved to `roadmaps/archived/`, its great-grandparent); INDEX.md is that root's
  # sibling file, matching the layout `plastic-roadmap`'s file-format doc defines.
  def index_path_for(roadmap_path)
    dir = File.dirname(roadmap_path)
    dir = File.dirname(dir) if File.basename(dir) == "archived"
    File.join(File.dirname(dir), "INDEX.md")
  end
  private_class_method :index_path_for

  def index_completed_date(index_path, id)
    return nil unless index_path && File.exist?(index_path)
    section_body(File.read(index_path), "Completed").each_line do |line|
      next unless line.strip.start_with?("- [#{id} ")
      m = line.match(/\)\s*—\s*(\d{4}-\d{2}-\d{2})\b/)
      return m[1] if m
    end
    nil
  end
  private_class_method :index_completed_date

  # The body text of a `## <heading>` section: everything after the heading line up to (but not
  # including) the next `## ` heading or end of file.
  def section_body(text, heading)
    m = text.match(/^##\s+#{Regexp.escape(heading)}\s*$(.*?)(?=^##\s|\z)/m)
    m ? m[1] : ""
  end
  private_class_method :section_body

  # Stable dedup on the `(event, detail)` pair, keeping the first occurrence in the given
  # (already chronological-then-backfill-appended) order.
  def dedup_pairs(lines)
    seen = []
    lines.select do |_t, event, detail|
      pair = [event, detail]
      next false if seen.include?(pair)
      seen << pair
      true
    end
  end
  private_class_method :dedup_pairs
end
