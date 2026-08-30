# encoding: UTF-8
# frozen_string_literal: true

# Handoff (intent 311): one session's hand-off, a pure rendering of its share
# of a day ledger (checklist.md and savepoint.md), written into the day
# directory as handoff--<session>.md at every tick, at PreCompact, and at
# close. Derived and regenerable: every write renders in full, so a lost or
# stale copy costs nothing. No environment reads; every path is injected.

require "fileutils"
require_relative "session_ledger"

module Handoff
  module_function

  TRIGGERS = %w[tick precompact close].freeze
  BUDGET = 4096
  LIST_CAP = 20
  RECENT_CAP = 10
  OPEN_STATES = %i[open pending].freeze
  # Trimmed first when the budget is exceeded; Open is the last to shrink.
  TRIM_ORDER = %i[others recent done open].freeze
  RESUME = "Say continue; the day summary at boot and this file carry the state."

  SAVEPOINT_TAIL_RE = /\A\[([^\]]*)\] \[([^\]]*)\] (.*)\z/m
  private_constant :SAVEPOINT_TAIL_RE

  def path_for(store, day, session)
    File.join(SessionLedger.day_dir(store, day), "handoff--#{session}.md")
  end

  # The day this session's hand-off belongs to: the pointer's day id, today
  # when no pointer exists, nil when the pointer names an intent (an auto
  # team owns that session's record, so the day ledger has nothing of it).
  def day_for(store, session, today:)
    path = SessionLedger.pointer_path(store, session)
    return today unless File.exist?(path)

    value = File.read(path).strip
    SessionLedger.valid_day_id?(value) ? value : nil
  end

  # --- readers ---------------------------------------------------------------------

  def read_items(store, day)
    SessionLedger.read_locked(SessionLedger.checklist_path(store, day))
                 .each_line.filter_map { |l| SessionLedger.parse_checklist_line(l) }
  end

  # Parsed savepoint lines, file order: {time:, event:, session:, project:,
  # summary:}. A line that does not follow the ledger grammar is skipped.
  def read_savepoint(store, day)
    SessionLedger.read_locked(SessionLedger.savepoint_path(store, day)).each_line.filter_map do |raw|
      line = raw.chomp.scrub
      next if line.empty?

      time, event, rest = line.split(/\s{2,}/, 3)
      next unless time && event && rest

      match = SAVEPOINT_TAIL_RE.match(rest)
      next unless match

      { time: time, event: event, session: match[1], project: match[2], summary: match[3] }
    end
  end

  # --- rendering, pure -----------------------------------------------------------

  def render(store:, day:, session:, trigger:, now: Time.now)
    raise ArgumentError, "unknown trigger: #{trigger.inspect}" unless TRIGGERS.include?(trigger)

    items = read_items(store, day)
    mine = items.select { |i| i[:session] == session }
    lists = {
      open: mine.select { |i| OPEN_STATES.include?(i[:state]) }.map { |i| item_line(i) },
      done: mine.select { |i| i[:state] == :done }.map { |i| item_line(i) },
      recent: read_savepoint(store, day).select { |e| e[:session] == session }.map { |e| recent_line(e) },
      others: others_lines(items, session),
    }
    hidden = Hash.new(0)
    cap!(lists, hidden, :open, LIST_CAP)
    cap!(lists, hidden, :done, LIST_CAP)
    cap!(lists, hidden, :recent, RECENT_CAP)

    header = [
      "# Hand-off: session #{session}, #{day}",
      "",
      "Written #{now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')} at #{trigger}",
      "",
    ]
    loop do
      text = compose(header, lists, hidden)
      return text if text.bytesize <= BUDGET

      key = TRIM_ORDER.find { |k| !lists[k].empty? }
      return text unless key

      # Open, Done, and Recent keep their newest entries; Others has no order.
      key == :others ? lists[key].pop : lists[key].shift
      hidden[key] += 1
    end
  end

  # Keeps the newest `cap` lines (the file is chronological) and counts the rest.
  def cap!(lists, hidden, key, cap)
    return unless lists[key].size > cap

    hidden[key] += lists[key].size - cap
    lists[key] = lists[key].last(cap)
  end

  def compose(header, lists, hidden)
    sections = [
      section("Open", lists[:open], hidden[:open]),
      section("Done", lists[:done], hidden[:done]),
      section("Recent", lists[:recent], hidden[:recent]),
      section("Others today", lists[:others], hidden[:others]),
      "## Resume\n#{RESUME}\n",
    ]
    (header + sections.compact).join("\n")
  end

  def section(title, lines, hidden)
    return nil if lines.empty? && hidden.zero?

    body = lines.dup
    body << "(+#{hidden} more)" if hidden.positive?
    "## #{title}\n#{body.join("\n")}\n"
  end

  def item_line(item)
    "- [#{item[:project]}] #{item[:summary]}"
  end

  def recent_line(event)
    "- #{event[:time][11, 5]}Z #{event[:event]} #{event[:summary]}"
  end

  def others_lines(items, session)
    items.reject { |i| i[:session] == session }
         .group_by { |i| i[:session] }
         .sort
         .map do |sid, theirs|
      open = theirs.count { |i| OPEN_STATES.include?(i[:state]) }
      done = theirs.count { |i| i[:state] == :done }
      "- #{sid}: #{open} open, #{done} done"
    end
  end

  # --- writing -------------------------------------------------------------------

  # Opens the day first (a tick after midnight never fails), renders, and
  # writes through a temp file and rename so a crash leaves no partial
  # hand-off. Returns the path. With `templates: nil` the day is not
  # scaffolded, only its directory ensured.
  def write(store:, day:, session:, trigger:, templates:, now: Time.now)
    if templates
      SessionLedger.open_day(store: store, day: day, templates: templates, author: session)
    else
      FileUtils.mkdir_p(SessionLedger.day_dir(store, day))
    end
    text = render(store: store, day: day, session: session, trigger: trigger, now: now)
    target = path_for(store, day, session)
    tmp = File.join(File.dirname(target), ".handoff-#{session}.tmp")
    File.write(tmp, text)
    File.rename(tmp, target)
    target
  end
end
