# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/guarded_append"

# Intent 335 (G2), S1: the shared fail-closed write guard. Matrix rows 1.1-1.15 in
# actions/ACTION_1.md. Every test is hermetic: a Dir.mktmpdir fixture, injected
# flock/sleeper seams, no environment read, no network.
class GuardedAppendTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("guarded-append")
    @path = File.join(@dir, "savepoint.md")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  # 1.1 - append to a new file
  def test_call_creates_the_file_and_appends_the_line
    refute File.exist?(@path)
    result = GuardedAppend.call(@path) { |_content| "n1  running\n" }
    assert_equal :written, result
    assert File.exist?(@path)
    assert_equal "n1  running\n", File.read(@path)
    assert File.read(@path).end_with?("\n")
  end

  # 1.2 - append to an existing file
  def test_call_appends_after_existing_content
    File.write(@path, "n1  planned\n")
    GuardedAppend.call(@path) { |_content| "n1  running\n" }
    assert_equal "n1  planned\nn1  running\n", File.read(@path)
  end

  # 1.3 - the block is yielded the current, live content
  def test_block_receives_the_current_file_content
    File.write(@path, "n1  planned\n")
    seen = nil
    GuardedAppend.call(@path) do |content|
      seen = content
      nil
    end
    assert_equal "n1  planned\n", seen
  end

  # 1.4 - a block returning nil writes nothing
  def test_nil_from_the_block_writes_nothing_and_returns_refused
    File.write(@path, "n1  planned\n")
    result = GuardedAppend.call(@path) { |_content| nil }
    assert_equal :refused, result
    assert_equal "n1  planned\n", File.read(@path)
  end

  # 1.5 - contended lock (injected flock always raising EWOULDBLOCK) raises Unavailable
  def test_contended_lock_raises_unavailable_after_five_attempts
    flock = ->(_handle, _mode) { raise Errno::EWOULDBLOCK }
    sleeper = ->(_seconds) { nil }
    error = assert_raises(GuardedAppend::Unavailable) do
      GuardedAppend.call(@path, flock: flock, sleeper: sleeper) { |_c| "line\n" }
    end
    assert_match(/lock/i, error.message)
  end

  # 1.6 - exactly five attempts, no more, no fewer
  def test_five_attempts_are_made_before_giving_up
    attempts = 0
    flock = lambda do |_handle, _mode|
      attempts += 1
      raise Errno::EWOULDBLOCK
    end
    sleeper = ->(_seconds) { nil }
    assert_raises(GuardedAppend::Unavailable) do
      GuardedAppend.call(@path, flock: flock, sleeper: sleeper) { |_c| "line\n" }
    end
    assert_equal 5, attempts
  end

  # 1.7 - the total backoff budget is five sleeps of twenty milliseconds
  def test_the_total_backoff_budget_is_five_sleeps_of_twenty_milliseconds
    sleeps = []
    flock = ->(_handle, _mode) { raise Errno::EWOULDBLOCK }
    sleeper = ->(seconds) { sleeps << seconds }
    assert_raises(GuardedAppend::Unavailable) do
      GuardedAppend.call(@path, flock: flock, sleeper: sleeper) { |_c| "line\n" }
    end
    assert_equal [0.02, 0.02, 0.02, 0.02, 0.02], sleeps
  end

  # 1.8 - a lock that succeeds on the third attempt still writes the line
  def test_a_lock_that_succeeds_on_attempt_three_writes_the_line
    attempts = 0
    flock = lambda do |handle, mode|
      next handle.flock(mode) unless mode == (File::LOCK_EX | File::LOCK_NB)

      attempts += 1
      attempts < 3 ? raise(Errno::EWOULDBLOCK) : handle.flock(mode)
    end
    sleeper = ->(_seconds) { nil }
    result = GuardedAppend.call(@path, flock: flock, sleeper: sleeper) { |_c| "n1  running\n" }
    assert_equal :written, result
    assert_equal 3, attempts
    assert_equal "n1  running\n", File.read(@path)
  end

  # 1.9 - strict: true, flock unsupported -> raise Unavailable, write nothing
  def test_strict_systemcallerror_raises_unavailable_and_writes_nothing
    File.write(@path, "n1  planned\n")
    flock = ->(_handle, _mode) { raise Errno::ENOTSUP, "flock not supported" }
    assert_raises(GuardedAppend::Unavailable) do
      GuardedAppend.call(@path, strict: true, flock: flock) { |_c| "n1  running\n" }
    end
    assert_equal "n1  planned\n", File.read(@path)
  end

  # 1.10 - strict: false, flock unsupported -> proceeds unguarded, RoadmapSavepoint's
  # existing always-writes contract stays intact on such a filesystem
  def test_non_strict_systemcallerror_writes_the_line_unguarded
    File.write(@path, "n1  planned\n")
    flock = ->(_handle, _mode) { raise Errno::ENOTSUP, "flock not supported" }
    result = GuardedAppend.call(@path, strict: false, flock: flock) { |_c| "n1  running\n" }
    assert_equal :written, result
    assert_equal "n1  planned\nn1  running\n", File.read(@path)
  end

  # 1.11 - give-up path leaves a pre-existing file byte identical
  def test_unavailable_leaves_a_pre_existing_file_byte_identical
    File.write(@path, "n1  planned\n")
    before = File.read(@path)
    flock = ->(_handle, _mode) { raise Errno::EWOULDBLOCK }
    sleeper = ->(_seconds) { nil }
    assert_raises(GuardedAppend::Unavailable) do
      GuardedAppend.call(@path, flock: flock, sleeper: sleeper) { |_c| "n1  running\n" }
    end
    assert_equal before, File.read(@path)
  end

  # 7.9 (post-execution review) - the give-up path must not leave a zero-byte file
  # behind when the target did not exist before the call. Row 1.11 above only covers
  # the pre-existing-file half of the give-up path.
  def test_unavailable_does_not_leave_a_file_the_call_created
    refute File.exist?(@path)
    flock = ->(_handle, _mode) { raise Errno::EWOULDBLOCK }
    sleeper = ->(_seconds) { nil }
    assert_raises(GuardedAppend::Unavailable) do
      GuardedAppend.call(@path, flock: flock, sleeper: sleeper) { |_c| "n1  running\n" }
    end
    refute File.exist?(@path), "a failed attempt must not leave behind a file it created"
  end

  # 1.12 - unlock and close: a second call after a successful call succeeds
  def test_a_second_call_after_a_successful_call_succeeds
    GuardedAppend.call(@path) { |_c| "n1  running\n" }
    result = GuardedAppend.call(@path) { |_c| "n1  done gates=suite\n" }
    assert_equal :written, result
    assert_equal "n1  running\nn1  done gates=suite\n", File.read(@path)
  end

  # 1.13 - missing final newline is repaired before the append
  def test_a_file_not_ending_in_a_newline_gets_one_before_the_append
    File.write(@path, "n1  running holder=auto-ce5") # crash-truncated, no trailing LF
    GuardedAppend.call(@path) { |_c| "n1  reclaimed holder=auto-ce5 expired=2026-09-08T20:00:00Z\n" }
    assert_equal "n1  running holder=auto-ce5\n" \
                 "n1  reclaimed holder=auto-ce5 expired=2026-09-08T20:00:00Z\n",
                 File.read(@path)
  end

  # 1.14 - real mutual exclusion, fork-based (modelled on
  # test/session_ledger_concurrency_test.rb), proving the guard's central claim
  # against real OS-level flock rather than only an injected seam.
  def test_forked_writers_produce_one_line_each_with_no_interleaving
    writers = 6
    lib = File.expand_path("../scripts/lib/guarded_append.rb", __dir__)
    pids = (1..writers).map do |i|
      fork do
        require lib
        GuardedAppend.call(@path, retries: 50, backoff: 0.02) { |_c| "n1  running holder=w#{i}\n" }
        exit!(0)
      end
    end
    pids.each { |pid| Process.waitpid(pid) }

    lines = File.read(@path).lines
    assert_equal writers, lines.length, "every forked writer's line must be present, exactly once"
    lines.each do |line|
      assert line.end_with?("\n")
      assert_equal 1, line.scan("holder=").length, "a line must carry exactly one holder (no interleaving)"
    end
    holders = lines.map { |l| l[/holder=(\S+)/, 1] }
    assert_equal (1..writers).map { |i| "w#{i}" }.sort, holders.sort
  end

  # 1.15 - a missing parent directory raises ENOENT, not Unavailable
  def test_a_missing_parent_directory_raises_enoent_not_unavailable
    missing = File.join(@dir, "no-such-subdir", "savepoint.md")
    assert_raises(Errno::ENOENT) do
      GuardedAppend.call(missing) { |_c| "n1  running\n" }
    end
  end
end
