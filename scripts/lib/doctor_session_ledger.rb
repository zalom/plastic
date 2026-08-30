# encoding: UTF-8
# frozen_string_literal: true

require "time"
require_relative "session_ledger"

# DoctorSessionLedger (intent 308) - the `session_ledger` doctor category, mixed into
# Doctor. Two checks over the batch-1 store areas that Doctor's intent walker never
# visits (both are dot-prefixed, and the walker stays ignorant of them by design: see
# test/store_walker_compat_test.rb). They live in the GLOBAL store only: every writer of
# .tmp/ and .sessions/ (hook-capture, hook-record, hook-session-start, Arm, SessionClose)
# targets the global store, so a project scope gets no finding and no check.
#
# Read-only: the orphan check names directories and never removes one, because a
# heartbeat is only refreshed on prompts and edits, so an old heartbeat is evidence, not
# proof, that the session is gone. Fail-open: an unreadable directory is skipped, never
# raised. Depends on the including class for `plastic_home` and `check`.
module DoctorSessionLedger
  ORPHAN_TTL_SECONDS = 24 * 60 * 60

  # Seconds since the session's last heartbeat: the ISO-8601 content of `heartbeat`,
  # else that file's mtime, else the directory's mtime.
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
  end

  def check_session_ledger(scopes: nil, now: Time.now)
    return [] unless scopes.nil? || scopes.include?("global")

    store_dir = File.join(plastic_home, "store")
    orphans = orphaned_session_dirs(store_dir, now)
    shape = day_ledger_shape_problems(store_dir)

    checks = []
    checks << if orphans.empty?
                check(category: "session_ledger", name: "orphaned_session_tmp", status: "pass",
                      message: "No .tmp/<session>/ directory has a heartbeat older than " \
                               "#{ORPHAN_TTL_SECONDS / 3600} hours")
              else
                check(category: "session_ledger", name: "orphaned_session_tmp", status: "warn",
                      message: "#{orphans.size} .tmp/<session>/ director#{orphans.size == 1 ? "y" : "ies"} " \
                               "with a heartbeat older than #{ORPHAN_TTL_SECONDS / 3600} hours " \
                               "(the session close hook never ran)",
                      details: orphans, fixable: true,
                      fix_hint: "Remove each listed .tmp/<session>/ directory after confirming that " \
                                "session is gone: a live session rewrites its heartbeat on every " \
                                "prompt and edit, so only a listed directory may be removed, by hand.")
              end
    checks << if shape.empty?
                check(category: "session_ledger", name: "day_ledger_shape", status: "pass",
                      message: "Every .sessions/ entry is a YYYYMMDD day directory with its <day>.md file")
              else
                check(category: "session_ledger", name: "day_ledger_shape", status: "warn",
                      message: "#{shape.size} .sessions/ shape problem#{shape.size == 1 ? "" : "s"}",
                      details: shape, fixable: true,
                      fix_hint: "For a day directory missing its <day>.md, run " \
                                "`ruby ~/.plastic/scripts/file-session-intent --day <day> --carry-to " \
                                "<today> --store <store>`; rename or remove an entry that is not a " \
                                "YYYYMMDD day directory.")
              end
    checks
  end

  def orphaned_session_dirs(store_dir, now)
    tmp_root = SessionLedger.tmp_root(store_dir)
    return [] unless File.directory?(tmp_root)

    Dir.children(tmp_root).sort.filter_map do |name|
      dir = File.join(tmp_root, name)
      next unless File.directory?(dir)

      age = heartbeat_age(dir, now)
      next if age <= ORPHAN_TTL_SECONDS

      "global: #{dir} (session #{name}, last heartbeat #{(age / 3600).floor}h ago)"
    end
  rescue SystemCallError
    [] # unreadable .tmp/: nothing to report, never a crash
  end

  def day_ledger_shape_problems(store_dir)
    root = SessionLedger.sessions_root(store_dir)
    return [] unless File.directory?(root)

    Dir.children(root).sort.filter_map do |name|
      path = File.join(root, name)
      if !File.directory?(path)
        "global: .sessions/#{name} is not a directory (only day directories belong here)"
      elsif !SessionLedger.valid_day_id?(name)
        "global: .sessions/#{name} is not a YYYYMMDD day id"
      elsif !File.file?(SessionLedger.day_file(store_dir, name))
        "global: .sessions/#{name} has no #{name}.md day file"
      end
    end
  rescue SystemCallError
    [] # unreadable .sessions/: nothing to report, never a crash
  end
end
