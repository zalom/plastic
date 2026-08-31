# encoding: UTF-8
# frozen_string_literal: true

# DaySummary (intent 311): the block SessionStart injects at boot, a bounded
# rendering of the day ledger (open items, the last five done), the live
# auto intents (an Active intent with a fresh delivery lock, across the
# global and every project store), and the other sessions alive by their
# heartbeat. Never the raw ledger (296 D36). No environment reads; every
# path is injected.

require "time"
require_relative "session_ledger"
require_relative "handoff"
require_relative "lock"
require_relative "report_screen"

module DaySummary
  module_function

  # Every part at its cap with 80-character summaries is about 2.8 KB; the
  # budget is the safety net above that, not the working limit.
  BUDGET = 3072
  HEARTBEAT_TTL = 3600
  OPEN_CAP = 10
  DONE_CAP = 5
  LIVE_CAP = 5
  SESSIONS_CAP = 10
  LINE_MAX = 100
  # Trimmed first when the budget is exceeded; Open is the last to shrink.
  TRIM_ORDER = %i[others live done open].freeze
  TITLES = {
    open: "Open:",
    done: "Done, last five:",
    live: "Live auto intents:",
    others: "Other active sessions:",
  }.freeze
  ISO8601_RE = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\b/
  INDEX_DIR_RE = %r{store/([\w][\w.-]*?)(?:/|\))}
  private_constant :ISO8601_RE, :INDEX_DIR_RE

  def build(store:, day:, session:, home:, now: Time.now, heartbeat_ttl: HEARTBEAT_TTL)
    lists = {
      open: open_items(store, day),
      done: last_done(store, day),
      live: live_intents(home, now: now),
      others: active_sessions(store, session, now: now, ttl: heartbeat_ttl),
    }
    hidden = Hash.new(0)
    cap!(lists, hidden, :open, OPEN_CAP, keep: :newest)
    cap!(lists, hidden, :done, DONE_CAP, keep: :newest)
    cap!(lists, hidden, :live, LIVE_CAP, keep: :first)
    cap!(lists, hidden, :others, SESSIONS_CAP, keep: :first)
    return "" if lists.values.all?(&:empty?)

    loop do
      text = compose(day, lists, hidden)
      return text if text.bytesize <= BUDGET

      key = TRIM_ORDER.find { |k| !lists[k].empty? }
      return text unless key

      %i[open done].include?(key) ? lists[key].shift : lists[key].pop
      hidden[key] += 1
    end
  end

  # --- parts -------------------------------------------------------------------------

  def open_items(store, day)
    Handoff.read_items(store, day)
           .select { |i| Handoff::OPEN_STATES.include?(i[:state]) }
           .map { |i| "- [#{i[:session]}] [#{i[:project]}] #{Handoff.clip(i[:summary])}" }
  end

  def last_done(store, day)
    Handoff.read_savepoint(store, day)
           .select { |e| e[:event] == "Done" }
           .map { |e| "- [#{e[:session]}] [#{e[:project]}] #{Handoff.clip(e[:summary])}" }
  end

  # The global store plus every projects/<slug>/store, each with its INDEX
  # one level up, the way doctor enumerates them.
  def stores(home)
    list = [[File.join(home, "INDEX.md"), File.join(home, "store")]]
    projects_root = File.join(home, "projects")
    if File.directory?(projects_root)
      Dir.children(projects_root).sort.each do |slug|
        list << [File.join(projects_root, slug, "INDEX.md"), File.join(projects_root, slug, "store")]
      end
    end
    list
  end

  def active_dirs(index_path)
    return [] unless File.exist?(index_path)

    dirs = []
    current = nil
    File.foreach(index_path) do |line|
      if (m = line.match(/^##\s+(.+?)\s*$/))
        current = m[1]
        next
      end
      next unless current == "Active"

      line.scan(INDEX_DIR_RE) { |(dirname)| dirs << dirname unless dirs.include?(dirname) }
    end
    dirs
  end

  def live_intents(home, now:)
    stores(home).flat_map do |index_path, store_dir|
      active_dirs(index_path).filter_map do |dirname|
        dir = File.join(store_dir, dirname)
        next unless File.directory?(dir) && Lock.fresh?(dir, now: now)
        # A guided session's lock is live but not autonomous; a lock with no
        # run_mode (a 1.14 auto team) counts as auto. 317a (B9): when the lock
        # carries no run_mode, the outcome frontmatter stamp (D5) is asked
        # before defaulting, so a guided close never reads as auto.
        run_mode = (Lock.read(dir) || {})["run_mode"].to_s
        run_mode = ReportScreen.outcome_frontmatter(dir)["mode"].to_s if run_mode.empty?
        next if run_mode == "guided"

        id, slug = dirname.split("--", 2)
        "- #{id} #{slug}: #{last_savepoint_line(dir)}"
      end
    end
  rescue SystemCallError
    []
  end

  def last_savepoint_line(dir)
    path = File.join(dir, "savepoint.md")
    if File.exist?(path)
      File.readlines(path).reverse_each do |line|
        text = line.strip
        return text[0, LINE_MAX] if text.match?(ISO8601_RE)
      end
    end
    "(no savepoint yet)"
  rescue SystemCallError
    "(no savepoint yet)"
  end

  def active_sessions(store, session, now:, ttl:)
    tmp_root = SessionLedger.tmp_root(store)
    return [] unless File.directory?(tmp_root)

    Dir.children(tmp_root).sort.filter_map do |sid|
      next if sid == session || sid.start_with?(".")

      dir = File.join(tmp_root, sid)
      next unless File.directory?(dir)

      age = heartbeat_age(dir, now)
      next if age.nil? || age > ttl

      "- #{sid} (#{(age / 60).floor}m ago, on #{pointer_of(dir)})"
    end
  rescue SystemCallError
    []
  end

  # Seconds since the session's last heartbeat: the ISO-8601 content of
  # `heartbeat`, else that file's mtime, else the directory's mtime. The
  # same reading doctor's orphan check uses, inverted here for liveness.
  def heartbeat_age(dir, now)
    heartbeat = File.join(dir, "heartbeat")
    if File.file?(heartbeat)
      begin
        return now - Time.iso8601(File.read(heartbeat).strip)
      rescue ArgumentError, IOError, SystemCallError
        return now - File.mtime(heartbeat)
      end
    end
    now - File.mtime(dir)
  rescue SystemCallError
    nil
  end

  def pointer_of(dir)
    path = File.join(dir, "current")
    return "?" unless File.file?(path)

    value = File.read(path).strip
    value.empty? ? "?" : value[0, 80]
  rescue SystemCallError
    "?"
  end

  # --- rendering, pure -------------------------------------------------------------

  def cap!(lists, hidden, key, cap, keep:)
    return unless lists[key].size > cap

    hidden[key] += lists[key].size - cap
    lists[key] = keep == :newest ? lists[key].last(cap) : lists[key].first(cap)
  end

  def compose(day, lists, hidden)
    out = ["Day summary #{day}:"]
    TITLES.each do |key, title|
      next if lists[key].empty? && hidden[key].zero?

      out << title
      out.concat(lists[key])
      out << "(+#{hidden[key]} more)" if hidden[key].positive?
    end
    out.join("\n")
  end
end
