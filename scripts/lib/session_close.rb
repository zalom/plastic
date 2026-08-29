# encoding: UTF-8
# frozen_string_literal: true

# SessionClose (intent 301): the per-session close, run by hooks/close at
# SessionEnd. Cheap, fail-open, and a no-op for the reasons that do not end a
# session (`clear`, `resume`). Every job runs in its own rescue so one failure
# never stops the next. No environment reads; the hook script passes the
# store, today's day id, and the spawner in.

require "fileutils"
require_relative "session_ledger"

module SessionClose
  module_function

  NOOP_REASONS = %w[clear resume].freeze

  # The default spawner starts the day filer detached so a slow filing never
  # blocks the harness shutdown (Codex kills a SessionEnd hook after 3 s).
  def default_spawner(script)
    lambda do |args|
      pid = Process.spawn({ "RUBYOPT" => nil }, RbConfig.ruby, script, *args,
                          pgroup: true, in: File::NULL, out: File::NULL, err: File::NULL)
      Process.detach(pid)
    end
  end

  # Returns a small report hash; never raises.
  def run(payload:, store:, today:, spawner:, now: Time.now)
    report = { reason: nil, dropped: 0, removed_tmp: false, spawned: nil }
    reason = payload.is_a?(Hash) ? payload["reason"].to_s : ""
    report[:reason] = reason
    return report if NOOP_REASONS.include?(reason)

    session = SessionLedger.short_session_id(payload.is_a?(Hash) ? payload["session_id"] : nil, nil)
    return report if session.empty?

    pointer_day = safely { read_pointer_day(store, session) } || today
    project = "global"

    report[:dropped] = safely do
      checklist = SessionLedger.checklist_path(store, pointer_day)
      count = SessionLedger.flip_all(checklist, from: :pending, to: :dropped, session: session)
      if count.positive?
        SessionLedger.append_line(SessionLedger.savepoint_path(store, pointer_day),
                                  SessionLedger.savepoint_line("Note", session, project,
                                                               "dropped #{count} pending lines at close", now: now))
      end
      count
    end || 0

    report[:removed_tmp] = safely do
      dir = SessionLedger.session_tmp_dir(store, session)
      FileUtils.rm_rf(dir) if Dir.exist?(dir)
      true
    end || false

    if pointer_day < today
      report[:spawned] = safely do
        args = ["--day", pointer_day, "--carry-to", today, "--store", store]
        spawner.call(args)
        args
      end
    end
    report
  end

  # The pointer names the intent this session records into; a day id means
  # the day ledger. Anything else (an intent id) means an auto team owns the
  # record and the close touches no day ledger.
  def read_pointer_day(store, session)
    path = SessionLedger.pointer_path(store, session)
    return nil unless File.exist?(path)

    value = File.read(path).strip
    SessionLedger.valid_day_id?(value) ? value : nil
  end

  def safely
    yield
  rescue StandardError
    nil
  end
end
