# encoding: UTF-8

require "fileutils"
require_relative "../session_ledger"
require_relative "../day_summary"
require_relative "../read_config"

module SessionStartHook
  # Open or join today's day ledger, create the session tmp dir, write the
  # heartbeat, and append the joined-count line plus the day summary (344 n2,
  # spec D4). Best-effort: any failure here degrades to no ledger line.
  module DayLedger
    # What a day-ledger line needs from the boot: where the store and home
    # are, the process environment, and the session id the payload carried.
    Inputs = Struct.new(:plastic_home, :store_dir, :env, :payload_session_id)

    def self.lines(inputs)
      day = SessionLedger.day_id
      open_today(inputs.store_dir, day)
      sid = open_tmp_and_heartbeat(inputs)
      build_lines(inputs, day, sid)
    rescue
      []
    end

    def self.build_lines(inputs, day, sid)
      lines = [joined_line(inputs.store_dir, day)]
      summary = build_summary(inputs, day, sid)
      lines << summary unless summary.empty?
      lines
    end

    # ReadConfig.resolve defaults to ENV["PLASTIC_HOME"], the real global
    # config, not the hook's own plastic_home: the author setting has always
    # been a real-environment lookup here, matching the prior backtick call's
    # inherited (never overridden) PLASTIC_HOME.
    def self.open_today(store_dir, day)
      author = ReadConfig.resolve("author").to_s.strip
      author = "session" if author.empty?
      templates = File.expand_path("../../../templates", __dir__)
      SessionLedger.open_day(store: store_dir, day: day, templates: templates, author: author)
    end

    def self.open_tmp_and_heartbeat(inputs)
      store_dir = inputs.store_dir
      sid = resolve_session_id(inputs)
      prepare_tmp_dir(store_dir, sid)
      sid
    end

    def self.prepare_tmp_dir(store_dir, sid)
      SessionLedger.ensure_tmp_root(store_dir)
      FileUtils.mkdir_p(SessionLedger.session_tmp_dir(store_dir, sid))
      write_heartbeat(store_dir, sid)
    end

    def self.resolve_session_id(inputs)
      payload_session_id = inputs.payload_session_id
      session = payload_session_id.empty? ? (inputs.env["CLAUDE_CODE_SESSION_ID"] || Process.pid.to_s) : payload_session_id
      SessionLedger.short_session_id(nil, session)
    end

    def self.write_heartbeat(store_dir, sid)
      File.write(SessionLedger.heartbeat_path(store_dir, sid), "#{Time.now.utc.iso8601}\n")
    end

    def self.joined_line(store_dir, day)
      open_count, pending_count = count_checklist_states(store_dir, day)
      "PLASTIC: day ledger #{day} joined (#{open_count} open items, #{pending_count} pending)"
    end

    def self.count_checklist_states(store_dir, day)
      checklist = SessionLedger.checklist_path(store_dir, day)
      return [0, 0] unless File.exist?(checklist)

      tally = state_tally(checklist)
      [tally[:open] || 0, tally[:pending] || 0]
    end

    def self.state_tally(checklist)
      File.readlines(checklist)
        .filter_map { |line| SessionLedger.parse_checklist_line(line) }
        .map { |entry| entry[:state] }
        .tally
    end

    def self.build_summary(inputs, day, sid)
      DaySummary.build(store: inputs.store_dir, day: day, session: sid, home: inputs.plastic_home, now: Time.now)
    rescue
      ""
    end
  end
end
