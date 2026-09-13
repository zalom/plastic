# encoding: UTF-8
# frozen_string_literal: true

# SessionClose (intent 301): the per-session close, run by hooks/close at
# SessionEnd. Cheap, fail-open, and a no-op for the reasons that do not end a
# session (`clear`, `resume`). Every job runs in its own rescue so one failure
# never stops the next. No environment reads; the hook script passes the
# store, today's day id, and the spawner in.

require "fileutils"
require_relative "session_ledger"
require_relative "handoff"

module SessionClose
  module_function

  NOOP_REASONS = %w[clear resume].freeze

  # The default hand-off writer (intent 311, spec D6): renders this session's
  # share of its session day (SessionLedger.session_day, graph.md D7) into
  # handoff--<session>.md before the tmp dir goes. The hook script builds it
  # with the shipped templates dir.
  def default_handoff(templates)
    lambda do |store, day, session|
      Handoff.write(store: store, day: day, session: session, trigger: "close", templates: templates)
    end
  end

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
  def run(payload:, store:, today:, spawner:, handoff: nil, now: Time.now)
    report = { reason: nil, dropped: 0, removed_tmp: false, spawned: nil, handoff: false }
    reason = payload.is_a?(Hash) ? payload["reason"].to_s : ""
    report[:reason] = reason
    return report if NOOP_REASONS.include?(reason)

    session = SessionLedger.short_session_id(payload.is_a?(Hash) ? payload["session_id"] : nil, nil)
    return report if session.empty?

    session_day = safely { SessionLedger.session_day(store, session, today: today) } || today
    project = "global"

    report[:dropped] = safely do
      checklist = SessionLedger.checklist_path(store, session_day)
      count = SessionLedger.flip_all(checklist, from: :pending, to: :dropped, session: session)
      if count.positive?
        SessionLedger.append_line(SessionLedger.savepoint_path(store, session_day),
                                  SessionLedger.savepoint_line("Note", session, project,
                                                               "dropped #{count} pending lines at close", now: now))
      end
      count
    end || 0

    # The hand-off (intent 311, spec D6) is written after the drop, so it
    # reflects it, and before the tmp dir goes. A session with no line in the
    # day ledger's window falls back to today, the same as the drop above.
    if handoff
      report[:handoff] = safely do
        handoff.call(store, session_day, session)
        true
      end || false
    end

    report[:removed_tmp] = safely do
      dir = SessionLedger.session_tmp_dir(store, session)
      FileUtils.rm_rf(dir) if Dir.exist?(dir)
      true
    end || false

    if session_day < today
      report[:spawned] = safely do
        args = ["--day", session_day, "--carry-to", today, "--store", store]
        spawner.call(args)
        args
      end
    end
    report
  end

  def safely
    yield
  rescue StandardError
    nil
  end
end
