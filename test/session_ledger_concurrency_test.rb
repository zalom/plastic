# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/session_ledger"

# Intent 297, task 4: the two-process flock race (spec D8). Several processes
# append to the SAME checklist.md and savepoint.md concurrently; every line
# must land intact, in an exact and complete count, with no lost or
# interleaved bytes. Every spawn clears CLAUDE_CODE_SESSION_ID, and every
# subprocess env carries PLASTIC_HOME and PLASTIC_TMP pointed at the
# Dir.mktmpdir root, per the hermeticity contract.
class SessionLedgerConcurrencyTest < Minitest::Test
  APPEND_LEDGER = File.expand_path("../scripts/append-ledger", __dir__)
  LIB = File.expand_path("../scripts/lib/session_ledger.rb", __dir__)
  TEMPLATES = File.expand_path("../templates", __dir__)

  WRITER_SESSIONS = %w[aaaaaaa1 aaaaaaa2 aaaaaaa3 aaaaaaa4 aaaaaaa5 aaaaaaa6].freeze
  APPENDS_PER_WRITER = 30

  # A small in-process worker: loops APPENDS_PER_WRITER times inside ONE
  # spawned process, calling SessionLedger.append_line directly (the same
  # locked-write path scripts/append-ledger's pending verb calls), so the
  # appends actually contend against each other rather than a fresh process
  # winning the lock in turn.
  WORKER_SCRIPT = <<~'RUBY'
    session = ARGV[0]
    path = ARGV[1]
    header = ARGV[2]
    count = ARGV[3].to_i
    lib = ARGV[4]
    require lib
    count.times do |i|
      summary = "#{session}-#{i}"
      line = SessionLedger.checklist_line(:pending, session, "plastic", summary)
      SessionLedger.append_line(path, line, header: header)
    end
  RUBY

  def setup
    @home = Dir.mktmpdir("session-ledger-race-home")
    @tmp = Dir.mktmpdir("session-ledger-race-tmp")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    @day = "20260829"
    @checklist_path = SessionLedger.checklist_path(@store, @day)
    @savepoint_path = SessionLedger.savepoint_path(@store, @day)
    FileUtils.mkdir_p(SessionLedger.day_dir(@store, @day))
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp)
  end

  def base_env
    { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_HOME" => @home, "PLASTIC_TMP" => @tmp }
  end

  def spawn_worker(session)
    header = SessionLedger.checklist_header(@day)
    IO.popen(base_env, [RbConfig.ruby, "-e", WORKER_SCRIPT, session, @checklist_path, header,
                        APPENDS_PER_WRITER.to_s, LIB])
  end

  def reap(handles)
    handles.each do |io|
      io.read
      io.close
      refute_equal false, $?.success?, "a worker process exited non-zero"
    end
  end

  # --- the checklist.md race ------------------------------------------------------

  def test_concurrent_appends_leave_every_checklist_line_intact_and_exact
    handles = WRITER_SESSIONS.map { |session| spawn_worker(session) }
    reap(handles)

    content = File.read(@checklist_path)
    lines = content.lines

    header_occurrences = content.scan("# Checklist: session ledger #{@day}").length
    assert_equal 1, header_occurrences, "the header must appear exactly once"

    body_lines = lines.drop(2) # header line + blank line
    expected_total = WRITER_SESSIONS.length * APPENDS_PER_WRITER
    assert_equal expected_total, body_lines.length, "every checklist line must be present, exactly once"

    parsed = body_lines.map { |line| SessionLedger.parse_checklist_line(line) }
    assert parsed.all?, "every checklist line must parse (a nil here is a torn write)"

    body_lines.each do |line|
      assert line.end_with?("\n"), "every line must end in LF"
      assert_equal 1, line.scan("- [").length, "a line must carry exactly one marker (no interleaving)"
    end

    issued_summaries = WRITER_SESSIONS.each_with_object([]) do |session, acc|
      APPENDS_PER_WRITER.times { |i| acc << "#{session}-#{i}" }
    end

    parsed_summaries = parsed.map { |h| h[:summary] }
    assert_equal issued_summaries.sort, parsed_summaries.sort,
      "every issued summary must appear exactly once, with none lost, duplicated, or malformed"

    by_session = parsed.group_by { |h| h[:session] }
    WRITER_SESSIONS.each do |session|
      own = by_session.fetch(session, [])
      assert_equal APPENDS_PER_WRITER, own.length, "session #{session} lost or gained lines"
      expected = (0...APPENDS_PER_WRITER).map { |i| "#{session}-#{i}" }
      assert_equal expected.sort, own.map { |h| h[:summary] }.sort
    end
  end

  def test_no_sibling_lock_file_after_the_checklist_race
    handles = WRITER_SESSIONS.map { |session| spawn_worker(session) }
    reap(handles)

    entries = Dir.children(File.dirname(@checklist_path))
    refute entries.any? { |e| e.end_with?(".lock") }
  end

  def test_inode_is_stable_across_the_checklist_race
    seed_line = SessionLedger.checklist_line(:pending, "seedseed", "plastic", "seed")
    SessionLedger.append_line(@checklist_path, seed_line, header: SessionLedger.checklist_header(@day))
    ino_before = File.stat(@checklist_path).ino

    handles = WRITER_SESSIONS.map { |session| spawn_worker(session) }
    reap(handles)

    ino_after = File.stat(@checklist_path).ino
    assert_equal ino_before, ino_after
  end

  # --- the savepoint.md race, driven through the append-ledger CLI ------------------------

  def test_concurrent_savepoint_appends_leave_every_line_intact_and_exact
    writers = 6
    handles = (1..writers).map do |i|
      IO.popen(base_env, [RbConfig.ruby, APPEND_LEDGER, "--store", @store, "--templates", TEMPLATES,
                          "--day", @day, "--session", "bbbbbbb#{i}", "--project", "plastic",
                          "savepoint", "--event", "Note", "concurrent note #{i}"])
    end
    reap(handles)

    content = File.read(@savepoint_path)
    lines = content.lines

    assert_equal writers, lines.length, "every savepoint append must be present, exactly once"
    lines.each do |line|
      assert line.end_with?("\n")
      parts = line.chomp.split(/\s{2,}/)
      assert_equal 3, parts.length, "a torn or interleaved savepoint line would not split into three parts"
    end

    notes = (1..writers).map { |i| "concurrent note #{i}" }
    found = lines.map { |line| line.chomp.split(/\s{2,}/).last.sub(/\A\[[^\]]+\] \[[^\]]+\] /, "") }
    assert_equal notes.sort, found.sort
  end
end
