require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/lock"

# Proves the atomicity and mutual-exclusion guarantees added to Lock.write
# (intent 232, AC1-AC6): no torn read, no lost update across a whole
# read-modify-write, bounded contention (never a hang), previous content
# left byte-for-byte intact on a failed write, purity preserved, and the new
# sibling guard file breaks nothing that walks the intent dir.
class LockAtomicWriteTest < Minitest::Test
  LOCK_RB = File.expand_path("../scripts/lib/lock.rb", __dir__)
  DRIVER = File.expand_path("support/lock_delegate_writer.rb", __dir__)

  def setup
    @store = Dir.mktmpdir("lock-atomic-store")
    @dir = File.join(@store, "232--demo")
    FileUtils.mkdir_p(@dir)
  end

  def teardown
    FileUtils.rm_rf(@store)
  end

  # --- AC1: torn reads --------------------------------------------------

  def test_a_concurrent_reader_never_sees_a_partial_lock_file
    Lock.write(@dir, large_payload)

    sentinel = "SENTINEL-FILE-MISSING"
    observations = []
    reader = Thread.new do
      600.times do
        observations << begin
          File.binread(Lock.path(@dir))
        rescue Errno::ENOENT
          sentinel
        end
      end
    end

    300.times do |i|
      payload = large_payload
      payload["acquired_at"] = "2026-01-01T00:00:%02dZ" % (i % 60)
      Lock.write(@dir, payload)
    end

    reader.join

    observations.each do |raw|
      refute_equal sentinel, raw,
        "an atomic rename replace must never leave the target path momentarily missing"
      parsed = JSON.parse(raw)
      assert_kind_of Hash, parsed
      assert parsed.key?("owner_session"),
        "a reader must see the complete previous content or the complete new content, " \
        "never a partial file"
    end
  end

  def test_write_leaves_no_temp_file_behind
    Lock.write(@dir, large_payload)
    assert_empty Dir.glob(File.join(@dir, "*.tmp*")), "no sibling temp file on the happy path"
    assert_equal ["delivery.lock"], Dir.children(@dir).sort
  end

  def test_the_temp_path_is_a_sibling_covered_by_the_store_gitignore_rule
    temp = Lock.write_temp_path(@dir)
    assert_equal @dir, File.dirname(temp),
      "the temp file must be a sibling in the intent dir, never a system tmpdir (EXDEV)"
    assert temp.end_with?(".lock"),
      "the temp name must end in .lock so an orphan left by a crash between the write " \
      "and the rename is covered by ~/.plastic/.gitignore's existing *.lock rule, not " \
      "committed by the store's git add -A auto-commit"
  end

  def test_write_replaces_the_file_by_rename_not_in_place_truncation
    Lock.write(@dir, large_payload)
    before_ino = File.stat(Lock.path(@dir)).ino
    Lock.write(@dir, large_payload)
    after_ino = File.stat(Lock.path(@dir)).ino
    refute_equal before_ino, after_ino,
      "a rename replace swaps the inode; an in-place File.write would not"
  end

  # --- AC2: lost updates --------------------------------------------------

  def test_two_concurrent_processes_both_register_every_delegate
    Lock.acquire(@dir, session: "owner-1")

    results = {}
    threads = %w[alpha beta].map do |prefix|
      Thread.new do
        results[prefix] = Open3.capture3(RbConfig.ruby, DRIVER, LOCK_RB, @dir, "owner-1", prefix, "25")
      end
    end
    threads.each(&:join)

    results.each do |prefix, (stdout, stderr, status)|
      assert status.success?,
        "#{prefix} driver must exit 0: stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
    end

    data = Lock.read(@dir)
    expected = (0..24).flat_map { |i| ["alpha-#{i}", "beta-#{i}"] }
    expected.each do |delegate|
      assert_includes data["delegates"], delegate, "delegate #{delegate} must survive both writers"
    end
    assert_equal 50, data["delegate_activity"].size,
      "all 50 activity records survive bounded_delegate_activity because every one is active"
  end

  # --- AC3: bounded contention, never a hang -----------------------------

  def test_write_guard_returns_within_an_injected_budget_when_the_guard_is_held
    Lock.write(@dir, large_payload)
    handle = File.open(Lock.write_guard_path(@dir), File::CREAT | File::RDWR, 0o644)
    handle.flock(File::LOCK_EX)

    begin
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Lock.with_write_guard(@dir, guard_timeout: 0.2, guard_retry: 0.005) do
        Lock.write(@dir, small_payload)
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_operator elapsed, :>=, 0.2, "must spend at least the injected budget contending"
      assert_operator elapsed, :<, 2.0, "must stay well under the 2 second ceiling"
      assert_equal small_payload["owner_session"], Lock.read(@dir)["owner_session"],
        "the write must still happen atomically after the guard times out"
    ensure
      handle.flock(File::LOCK_UN)
      handle.close
    end
  end

  def test_add_delegate_never_hangs_when_the_guard_is_held_at_the_real_default
    Lock.acquire(@dir, session: "owner-1")
    handle = File.open(Lock.write_guard_path(@dir), File::CREAT | File::RDWR, 0o644)
    handle.flock(File::LOCK_EX)

    begin
      assert_operator Lock::WRITE_GUARD_TIMEOUT_SECONDS, :>, 0
      assert_operator Lock::WRITE_GUARD_TIMEOUT_SECONDS, :<=, 5.0

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = Lock.add_delegate(@dir, delegate: "d-1", session: "owner-1")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_equal true, result
      assert_operator elapsed, :<, 10.0,
        "must return well under 10 seconds even at the shipped default budget"
      assert_includes Lock.read(@dir)["delegates"], "d-1"
    ensure
      handle.flock(File::LOCK_UN)
      handle.close
    end
  end

  # --- AC4: a failed write leaves the previous content intact -----------

  def test_a_failed_write_leaves_the_previous_lock_byte_for_byte_intact
    skip "root ignores directory permissions" if Process.uid.zero?

    Lock.acquire(@dir, session: "owner-1")
    before = File.binread(Lock.path(@dir))
    File.chmod(0o500, @dir)

    begin
      assert_raises(SystemCallError) { Lock.write(@dir, small_payload) }
      assert_equal before, File.binread(Lock.path(@dir)),
        "the previous lock file must survive a failed write byte-for-byte"
    ensure
      File.chmod(0o700, @dir)
    end
  end

  # --- AC5: purity --------------------------------------------------------

  def test_lock_rb_reads_no_env_and_shells_out_to_nothing
    # A plain substring search for "ENV" would false-positive on lock.rb's
    # OWN purity header (lock.rb:22-23: "nothing here reads ENV or
    # globals"), so this checks actual usage patterns (ENV[ / ENV.) on
    # non-comment lines, plus the other shell-out markers.
    code = File.readlines(LOCK_RB).reject { |line| line.strip.start_with?("#") }.join
    message = "lock.rb:22-23 promises pure and dependency-injected: no ENV read, nothing shelled out"

    refute_match(/\bENV\s*[\[.]/, code, message)
    refute_match(/\bOpen3\b/, code, message)
    refute_match(/IO\.popen/, code, message)
    refute_match(/\bsystem\(/, code, message)
    refute_match(/\bspawn\(/, code, message)
    refute_match(/%x[(\[{]/, code, message)
    refute_match(/`[^`]*`/, code, message)
  end

  # --- AC6: the sibling guard file breaks nothing that walks the intent dir

  def test_the_write_guard_is_not_a_lock_type
    # Lock.path(dir, type: "delivery.write") would render the same file name
    # as write_guard_path, and the exclusion at acquire, (TYPES -
    # [type]).first, silently checks only one other type, so a third TYPES
    # entry would break mutual exclusion (spec D3) with no error.
    assert_equal %w[delivery maintenance], Lock::TYPES
    guard_path = Lock.write_guard_path(@dir)
    assert_equal File.join(@dir, "delivery.write.lock"), guard_path
    refute_equal Lock.path(@dir), guard_path
  end

  def test_the_guard_file_is_inert_and_survives_release
    Lock.acquire(@dir, session: "owner-1")
    Lock.add_delegate(@dir, delegate: "d-1", session: "owner-1")

    guard_path = Lock.write_guard_path(@dir)
    assert File.exist?(guard_path)
    assert_equal 0, File.size(guard_path), "the guard is only ever an flock target, never written to"

    assert_equal "owner-1", Lock.read(@dir)["owner_session"]
    assert Lock.fresh?(@dir)
    refute Lock.corrupt?(@dir)
    assert_equal "fresh", Lock.who(@dir)["state"]
    assert_empty Claim.claims_status(@dir), "the guard file must never read as a claim"

    assert_equal :released, Lock.release(@dir, session: "owner-1")
    refute File.exist?(Lock.path(@dir)),
      "scripts/end-intent:558 and scripts/doctor.rb:718 key their exit contract on this"
    assert File.exist?(guard_path), "release must not delete an flock target (unlink-recreate race)"

    status, _data = Lock.acquire(@dir, session: "s2", type: "maintenance")
    assert_equal :acquired, status,
      "the leftover sibling guard file must not read as a fresh delivery lock to the D3 exclusion"
  end

  def test_a_store_wide_delivery_lock_glob_does_not_match_the_guard
    Lock.acquire(@dir, session: "owner-1")
    Lock.add_delegate(@dir, delegate: "d-1", session: "owner-1")

    # Reproduces scripts/lib/bridge.rb:1150, the only place in the repo that
    # globs lock files across a whole store. Every other intent-dir walk is
    # directory-only, .md-only, .claim-only, or .json-only.
    matches = Dir.glob(File.join(@store, "*", "delivery.lock"))
    assert_equal [Lock.path(@dir)], matches
  end

  private

  def large_payload
    delegates = Array.new(2000) { |i| "delegate-#{i}-#{'x' * 20}" }
    Lock.payload(session: "owner-1", type: "delivery", host: "test-host", now: Time.now,
                delegates: delegates)
  end

  def small_payload
    Lock.payload(session: "owner-2", type: "delivery", host: "test-host", now: Time.now)
  end
end
