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

  EVENTS = %w[created dispatched parked merged release handoff closed added reordered wave batch].freeze

  # Raised by grouping_section_body when a roadmap has neither '## Batches' (canonical, owner
  # ruling 145) nor '## Waves' (legacy) as its top-level grouping heading (intent 196): a
  # malformed roadmap must fail loudly, never silently parse as zero entries.
  class MissingGroupingHeading < StandardError; end

  # Canonical first, legacy fallback second. A roadmap file has exactly one of these, never both.
  GROUPING_HEADINGS = %w[Batches Waves].freeze

  # Keyword -> event classification for `rebuild`, checked top to bottom, first match wins.
  # Kept small and deterministic (action 1). Order matters: more specific/rarer words are
  # checked before the broader "wave"/"batch" fallbacks so an incidental "wave" or "batch"
  # mention in an otherwise classifiable line never shadows its real event.
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
    [/\bbatch(?:es)?\b/i, "batch"],
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

  # Public (intent 331c): a roadmap's own ledger, parsed into `[Time, event, detail]` triples in
  # file order - so a screen reader never re-derives the "<iso>  <event>  <detail>" line shape.
  # `roadmap_path` is the roadmap `.md` file, never the `.savepoint.md` sibling directly (mirrors
  # `ledger_path_for`'s own convention). No paired ledger file -> `[]`, never an invented event.
  def ledger_entries(roadmap_path)
    ledger_path = ledger_path_for(roadmap_path)
    return [] unless File.exist?(ledger_path)

    File.readlines(ledger_path).filter_map do |line|
      parts = line.strip.split(/\s{2,}/, 3)
      next nil unless parts.length == 3
      begin
        [Time.iso8601(parts[0]), parts[1], parts[2]]
      rescue ArgumentError
        nil
      end
    end
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
  # roadmap `.md`, which is read-only here), cross-checked against the roadmap's grouping
  # section (`## Batches`, or legacy `## Waves`) and the tier's INDEX so every `delivered` wave
  # entry has a `merged` line. Every timestamp comes from an on-disk source (the Log, or INDEX
  # `## Completed`); an entry with no recoverable timestamp is not emitted (D4, never invented).
  # Overwrites the ledger (the one operation allowed to rewrite it, matching
  # `Savepoint.rebuild_savepoint`). Returns the number of lines written.
  def rebuild(roadmap_path)
    text = File.read(roadmap_path)
    log_lines = classify_log(section_body(text, "Log"))
    delivered_ids = delivered_wave_ids(grouping_section_body(text, path: roadmap_path))
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

  # Public (intent 331c): the Log table on a roadmap's `delivered` screen classifies every
  # `## Log` line through this same keyword vocabulary, so a screen reader never grows a second
  # copy of KEYWORD_TABLE.
  def classify_event(text)
    hit = KEYWORD_TABLE.find { |regex, _event| text =~ regex }
    hit && hit[1]
  end

  WAVE_ENTRY = /\A-\s*\[([ xX])\]\s+(\S+)\s+.+—\s*(\S+)\s*\z/.freeze

  # Intent ids of every `[x] ... — delivered` entry in the roadmap's grouping section body
  # (`## Batches`, or legacy `## Waves`).
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

  # The one shared fix point for the Batches/Waves grammar (intent 196). '## Batches' is
  # canonical (owner ruling 145); '## Waves' is the legacy heading the three pre-ruling roadmaps
  # still use and must keep parsing forever (145 also forbids renaming those files). Public,
  # because roadmap_queue.rb calls it instead of holding its own copy of the heading string: that
  # file already depends one-directionally on this module (require_relative "roadmap_savepoint",
  # already calling `ledger_path_for`), so this is the smaller diff than a new shared module.
  # Raises MissingGroupingHeading, naming the offending path, when neither heading is present.
  def grouping_section_body(text, path: nil)
    heading = grouping_heading(text)
    unless heading
      raise MissingGroupingHeading,
            "#{path || '(unknown roadmap file)'}: found neither '## Batches' (canonical) nor " \
            "'## Waves' (legacy) grouping heading"
    end
    text.match(/^##\s+#{Regexp.escape(heading)}\s*$(.*?)(?=^##\s|\z)/m)[1]
  end

  # Public (intent 331c): "Batches" or "Waves", whichever grouping heading `text` carries - the
  # one owner of that label so a screen's own field row (and its entries table's column header)
  # never hand-picks between them a second way. nil when neither heading is present (mirrors
  # grouping_section_body's own detection, one call site cheaper than two).
  def grouping_heading(text)
    GROUPING_HEADINGS.find { |heading| text.match?(/^##\s+#{Regexp.escape(heading)}\s*$/) }
  end

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
