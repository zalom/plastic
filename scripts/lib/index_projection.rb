# encoding: UTF-8
# frozen_string_literal: true

require_relative "doctor_exclusions"

# IndexProjection (intent 337, n5): computes every intent's status from its
# own savepoint.md ledger, reads the status INDEX.md currently claims, and
# reports the drift between them. The ledger wins WHERE THE LEDGER SPEAKS
# (row 5.1/5.2): a REAL terminal line (Done delivered/abandoned, or a
# classifiable Done detail) beats a stale INDEX section. An intent whose
# ledger is silent (no terminal line) or absent (no savepoint.md at all)
# keeps the status INDEX already carries (row 5.13, folded at the
# 2026-09-10 plan review): 63 of 451 intents in the plastic store have no
# savepoint.md and 59 more never reach a Done line, and a literal reading
# would demote all of them. This module computes and compares only; it
# writes nothing (row 5.11) and reads no clock or environment variable.
module IndexProjection
  module_function

  INDEX_SECTIONS = %w[Active Future Completed Abandoned].freeze
  TERMINAL_STATUSES = %w[Completed Abandoned].freeze
  EXCLUSION_RULES = %w[savepoint_operational backfilled_complete].freeze

  def analyze(store_path)
    index_path = File.join(store_path, "INDEX.md")
    index_map = read_index(index_path)
    dir_ids = store_intent_ids(store_path)

    excluded = excluded_ids(index_path)

    drift = index_map.filter_map do |id, index_status|
      next if index_status == "Future" # 5.5: Future has no ledger counterpart
      next if excluded.include?(id) # 5.12

      ledger_status = ledger_status_for(store_path, id)
      next unless TERMINAL_STATUSES.include?(ledger_status) # 5.3/5.13
      next if ledger_status == index_status

      { id: id, index_status: index_status, ledger_status: ledger_status }
    end

    index_only = (index_map.keys - dir_ids).reject { |id| excluded.include?(id) }
                                            .map { |id| { id: id, index_status: index_map[id] } }
    directory_only = (dir_ids - index_map.keys).reject { |id| excluded.include?(id) }
                                                .map { |id| { id: id } }

    { ok: true, drift: drift, index_only: index_only, directory_only: directory_only, errors: [] }
  end

  # --- INDEX -------------------------------------------------------------------

  def read_index(index_path)
    map = {}
    return map unless File.exist?(index_path)

    text = read_utf8(index_path)
    INDEX_SECTIONS.each do |heading|
      section_body(text, heading).each_line do |line|
        stripped = line.strip
        next unless stripped.start_with?("- [")

        m = stripped.match(/\A-\s*\[(\S+)\s/)
        map[m[1]] = heading if m
      end
    end
    map
  end

  def section_body(text, heading)
    m = text.match(/^##\s+#{Regexp.escape(heading)}\s*$(.*?)(?=^##\s|\z)/m)
    m ? m[1] : ""
  end

  # --- store directories ---------------------------------------------------------

  def store_intent_ids(store_path)
    return [] unless Dir.exist?(store_path)

    Dir.entries(store_path).select { |e| e.include?("--") && File.directory?(File.join(store_path, e)) }
       .map { |e| e.split("--", 2).first }
  end

  def intent_dir_for(store_path, id)
    Dir.glob(File.join(store_path, "#{id}--*")).find { |p| File.directory?(p) }
  end

  # --- the ledger (savepoint.md) --------------------------------------------------

  # "Completed", "Abandoned", "Active" (no terminal line yet), "unknown" (no
  # directory or no savepoint.md), or "indeterminate" (a Done line whose
  # detail is neither delivered/merged nor abandoned, row 5.14).
  def ledger_status_for(store_path, id)
    dir = intent_dir_for(store_path, id)
    return "unknown" unless dir

    sp_path = File.join(dir, "savepoint.md")
    return "unknown" unless File.exist?(sp_path)

    parsed = complete_lines(read_utf8(sp_path)).filter_map { |l| parse_line(l) }
    last_done = parsed.reverse.find { |p| p[:kind] == "Done" }
    return "Active" unless last_done

    classify_done_detail(last_done[:detail]) || "indeterminate"
  end

  # Drop the trailing torn fragment: a savepoint line that never got its
  # closing newline because the process died mid-append (row 5.6). Works
  # whether the file ends in a newline (the dropped element is the empty
  # string split(-1) always yields after a final "\n") or not (the dropped
  # element is the torn fragment itself).
  def complete_lines(content)
    return [] if content.to_s.empty?

    lines = content.split("\n", -1)
    lines.pop
    lines.reject { |l| l.strip.empty? }
  end

  def parse_line(line)
    parts = line.strip.split(/\s{2,}/, 3)
    return nil unless parts.length == 3

    { time: parts[0], kind: parts[1], detail: parts[2] }
  end

  def classify_done_detail(detail)
    d = detail.to_s.strip
    return "Abandoned" if d.start_with?("abandoned")
    return "Completed" if d.start_with?("delivered") || d.start_with?("merged")

    nil
  end

  # --- doctor exclusions (row 5.12) -----------------------------------------------

  def excluded_ids(index_path)
    loaded = DoctorExclusions.load(index_path)
    EXCLUSION_RULES.flat_map { |rule| loaded[:rules][rule] || [] }.uniq
  end

  # --- utf-8 -----------------------------------------------------------------------

  def read_utf8(path)
    text = File.read(path)
    text.force_encoding(Encoding::UTF_8)
    text.valid_encoding? ? text : text.scrub("")
  end
end
