# encoding: UTF-8
# frozen_string_literal: true

# SessionBackfill (intent 301): file a session day ledger. The four backfilled
# documents are a pure function of the day's checklist.md and savepoint.md, so
# every run regenerates them in full and a rerun is correct by construction.
# The carry step deduplicates against the target day before it appends and
# flips the source line after, so a crash at any point leaves a rerun correct.
# Every ledger write goes through SessionLedger. No environment reads here;
# the CLI passes every path in.

require "date"
require "fileutils"
require "time"
require_relative "session_ledger"

module SessionBackfill
  module_function

  DOCS = ["spec.md", "plan.md", "actions/ACTION_1.md", "outcome.md"].freeze
  SAVEPOINT_RE = /\A(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\s{2,}(\S+)(?:\s{2,}(.*))?\z/m.freeze
  CARRIED_RE = / \(carried from \d{8}\)\z/.freeze
  FILER_SESSION = "filer"
  FILER_PROJECT = "global"
  SUMMARY_CAP = 200

  # --- reading ---------------------------------------------------------------

  def parse_savepoint_line(line)
    match = SAVEPOINT_RE.match(line.to_s.chomp.scrub)
    return nil unless match

    { timestamp: match[1], event: match[2], rest: match[3].to_s }
  end

  def read_items(dir)
    path = File.join(dir, "checklist.md")
    SessionLedger.read_locked(path).each_line.filter_map { |l| SessionLedger.parse_checklist_line(l) }
  end

  def read_savepoint_lines(dir)
    path = File.join(dir, "savepoint.md")
    SessionLedger.read_locked(path).each_line.map(&:chomp).reject(&:empty?)
  end

  # --- rendering, pure ---------------------------------------------------------

  def format_item(item)
    marker = SessionLedger::STATES.fetch(item[:state])
    "- [#{marker}] [#{item[:session]}] [#{item[:project]}] #{item[:summary]}"
  end

  def section(title, lines)
    body = lines.empty? ? "(none)" : lines.join("\n")
    "## #{title}\n#{body}\n"
  end

  def render(dir, day:)
    items = read_items(dir)
    steps = read_savepoint_lines(dir)
    requests = items.reject { |i| i[:state] == :dropped }.map { |i| "- [#{i[:session]}] [#{i[:project]}] #{i[:summary]}" }
    done = items.select { |i| i[:state] == :done }.map { |i| format_item(i) }
    carried = items.select { |i| i[:state] == :moved }.map { |i| format_item(i) }
    promoted = items.select { |i| i[:state] == :promoted }.map { |i| format_item(i) }
    disposition = done.empty? ? "abandoned" : "delivered"

    {
      "spec.md" => "# Spec: session ledger #{day}\n\n#{section('Requests', requests)}",
      "plan.md" => "# Plan: session ledger #{day}\n\n#{section('Steps', steps.map { |s| "- #{s}" })}",
      "actions/ACTION_1.md" => "# ACTION_1: session ledger #{day}\n\n#{section('Items', items.map { |i| format_item(i) })}",
      "outcome.md" => "---\ndisposition: #{disposition}\n---\n# Outcome: session ledger #{day}\n\n" \
                      "#{section('Delivered', done)}\n#{section('Carried', carried)}\n#{section('Promoted', promoted)}",
    }
  end

  # --- writing, atomic inside the day dir ----------------------------------------

  def write_atomic(dir, relative, content)
    target = File.join(dir, relative)
    FileUtils.mkdir_p(File.dirname(target))
    tmp = File.join(File.dirname(target), ".filing-#{File.basename(target)}")
    File.write(tmp, content)
    File.rename(tmp, target)
  end

  def write_docs(dir, docs)
    docs.each { |relative, content| write_atomic(dir, relative, content) }
  end

  # --- closed marker ---------------------------------------------------------------

  def closed_at(day_file)
    return nil unless File.exist?(day_file)

    frontmatter = File.read(day_file).split(/^---\s*$/, 3)[1].to_s
    value = frontmatter[/^closed:\s*(\S+)/, 1]
    value ? Time.iso8601(value) : nil
  rescue ArgumentError
    nil
  end

  def stamp_closed(day_file, now:)
    stamp = "closed: #{now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}\n"
    content = File.read(day_file)
    updated =
      if content =~ /^closed:.*\n/
        content.sub(/^closed:.*\n/, stamp)
      else
        parts = content.split(/^(---\s*\n)/, 3)
        # parts: ["", "---\n", frontmatter, "---\n", rest]
        parts.length >= 4 ? parts[0] + parts[1] + parts[2] + stamp + parts[3] + parts[4].to_s : content + stamp
      end
    write_atomic(File.dirname(day_file), File.basename(day_file), updated)
  end

  # A day is closed when it carries a closed: stamp and its checklist has not
  # been written since (integer-second comparison; a line appended within the
  # closing second waits for the next line).
  def closed?(store, day)
    closed = closed_at(SessionLedger.day_file(store, day))
    return false unless closed

    checklist = SessionLedger.checklist_path(store, day)
    return true unless File.exist?(checklist)

    File.mtime(checklist).to_i <= closed.to_i
  end

  # --- carry -------------------------------------------------------------------------

  def carried_summary(summary, from)
    suffix = " (carried from #{from})"
    base = SessionLedger.sanitize_summary(summary.sub(CARRIED_RE, ""))
    room = SUMMARY_CAP - suffix.length
    base = "#{base[0, room - 3]}..." if base.length > room
    base + suffix
  end

  def note(store, day, text, now:)
    SessionLedger.append_line(SessionLedger.savepoint_path(store, day),
                              SessionLedger.savepoint_line("Note", FILER_SESSION, FILER_PROJECT, text, now: now))
  end

  def carry(store:, from:, to:, templates:, author:, now: Time.now)
    SessionLedger.open_day(store: store, day: to, templates: templates, author: author, now: now)
    source = SessionLedger.checklist_path(store, from)
    target = SessionLedger.checklist_path(store, to)
    existing = read_items(SessionLedger.day_dir(store, to)).map { |i| [i[:session], i[:summary]] }
    count = 0
    read_items(SessionLedger.day_dir(store, from)).select { |i| i[:state] == :open }.each do |item|
      summary = carried_summary(item[:summary], from)
      unless existing.include?([item[:session], summary])
        SessionLedger.append_line(target, SessionLedger.checklist_line(:open, item[:session], item[:project], summary),
                                  header: SessionLedger.checklist_header(to))
        existing << [item[:session], summary]
      end
      SessionLedger.set_state(source, from: :open, to: :moved, session: item[:session], match: item[:summary])
      count += 1
    end
    return 0 if count.zero?

    note(store, from, "carried #{count} items to #{to}", now: now)
    note(store, to, "received #{count} items from #{from}", now: now)
    count
  end

  # --- the filer -----------------------------------------------------------------------

  # Returns :closed when the day is already filed and unchanged, else :filed.
  def file_day(store:, day:, templates:, author:, carry_to: nil, now: Time.now)
    SessionLedger.open_day(store: store, day: day, templates: templates, author: author, now: now)
    return :closed if closed?(store, day)

    dir = SessionLedger.day_dir(store, day)
    checklist = SessionLedger.checklist_path(store, day)
    dropped = SessionLedger.flip_all(checklist, from: :pending, to: :dropped)
    note(store, day, "dropped #{dropped} pending lines at filing", now: now) if dropped.positive?
    carry(store: store, from: day, to: carry_to, templates: templates, author: author, now: now) if carry_to
    write_docs(dir, render(dir, day: day))
    stamp = [Time.now, (File.exist?(checklist) ? File.mtime(checklist) : Time.at(0))].max
    stamp_closed(SessionLedger.day_file(store, day), now: stamp)
    :filed
  end
end
