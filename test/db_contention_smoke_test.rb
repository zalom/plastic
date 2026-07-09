require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"

require_relative "../scripts/lib/db"
require_relative "../scripts/lib/db/leases"

# Forked ~100-writer contention smoke test (intent 41, ACTION_3, AC2): proves
# the with_write BEGIN IMMEDIATE + bounded SQLITE_BUSY retry discipline holds
# under REAL multi-process contention against ONE shared plastic.db, and that
# Leases keeps exactly one live holder per (intent_id, artifact) grain even
# when many independent OS processes race it.
#
# This is the one sanctioned exception to single-process hermeticity
# (AGENTS.md / plan.md Notes): it still isolates its own Dir.mktmpdir store
# and never touches an ambient session id, only real forked children instead
# of threads, because threads inside one process would share a single SQLite
# connection's serialization and prove nothing about cross-process file
# locking.
class DbContentionSmokeTest < Minitest::Test
  WORKERS = 100
  ITERATIONS_PER_WORKER = 5

  def test_concurrent_writers_hold_exactly_one_holder_and_complete_all_writes
    skip "Process.fork unavailable on this platform" unless Process.respond_to?(:fork)

    store_home = Dir.mktmpdir("plastic-db-contention")
    marker_dir = File.join(store_home, "busy-markers")
    FileUtils.mkdir_p(marker_dir)

    # Warm the schema ONCE before forking: every child then connects through
    # the REAL production path (Schema.ensure! runs on every connect by
    # default), but Schema.ensure! fast-paths on PRAGMA user_version already
    # matching DDL_VERSION, so each child's ensure! is a plain read, never
    # the write-locking DDL batch. Children also inherit the already-loaded
    # sqlite3 gem from the parent, so forking 100 children is cheap and the
    # children's first write isn't itself an 18-statement DDL race.
    seed_conn = Plastic::DB.connect(store_home)
    refute_nil seed_conn, "sqlite3 gem must be available for this smoke test"
    seed_conn.close

    pids = (1..WORKERS).map do |worker_index|
      Process.fork { self.class.run_worker(store_home, worker_index, marker_dir) }
    end

    statuses = pids.map { |pid| Process.wait2(pid).last }

    failed = statuses.reject(&:success?)
    assert_empty failed, "every child must exit 0; #{failed.length} child(ren) failed"

    markers = Dir.glob(File.join(marker_dir, "*"))
    details = markers.map { |f| "#{File.basename(f)}: #{File.read(f)}" }
    assert_empty markers, "no child may hit an unrecovered SQLITE_BUSY or error:\n#{details.join("\n")}"

    conn = Plastic::DB.connect(store_home)
    total_events = conn.execute("SELECT COUNT(*) FROM savepoint_events").first.first
    assert_equal WORKERS * ITERATIONS_PER_WORKER, total_events,
                 "every worker iteration's savepoint_events write must have landed"

    multi_holder_grains = conn.execute(
      "SELECT intent_id, artifact, COUNT(*) AS live_count FROM lock_leases " \
      "WHERE released_at IS NULL GROUP BY intent_id, artifact HAVING live_count > 1"
    )
    assert_empty multi_holder_grains, "no (intent_id, artifact) grain may ever have more than one live holder"
  ensure
    FileUtils.rm_rf(store_home) if store_home
  end

  # Runs entirely inside a forked child. Opens its OWN connection to the
  # shared DB file (never inherits the parent's), hammers lease acquire +
  # release plus a savepoint_events append, then exits explicitly.
  #
  # Uses exit! (not exit) so Minitest::Autorun's at_exit hook never re-fires
  # inside the child; that is the standard fork+Minitest hazard and the
  # reason every path out of this method is an explicit exit!.
  def self.run_worker(store_home, worker_index, marker_dir)
    session = "contention-worker-#{worker_index}"
    conn = Plastic::DB.connect(store_home)
    unless conn
      File.write(File.join(marker_dir, "#{worker_index}-no-conn"), "1")
      exit!(1)
    end

    ITERATIONS_PER_WORKER.times do |i|
      # Sometimes-colliding intent_ids: half the iterations hit a small
      # shared pool of 10 ids (real, frequent collisions across workers),
      # half hit a worker-private id (uncontended baseline).
      intent_id = i.even? ? "contention-shared-#{worker_index % 10}" : "contention-#{worker_index}"

      status, = Plastic::DB::Leases.acquire(conn, intent_id, session: session, host: "smoke-host", ttl: 5, now: Time.now)
      if status == :fail_open
        File.write(File.join(marker_dir, "#{worker_index}-#{i}-acquire-busy"), "1")
      elsif status == :acquired || status == :owned
        release_status = Plastic::DB::Leases.release(conn, intent_id, session: session, now: Time.now)
        if release_status == :fail_open
          File.write(File.join(marker_dir, "#{worker_index}-#{i}-release-busy"), "1")
        end
      end
      # :held / :stale from a genuine collision is a healthy, expected
      # outcome (it proves mutual exclusion held), not a failure.

      event_result = Plastic::DB.with_write(conn) do |c|
        stamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
        c.execute(
          "INSERT INTO savepoint_events (intent_id, stage, event_type, actor_session, payload, occurred_at, created_at, updated_at) " \
          "VALUES (NULL, ?, ?, ?, ?, ?, ?, ?)",
          ["Exec", "contention-smoke", session, "{}", stamp, stamp, stamp]
        )
        :written
      end
      if event_result.nil?
        File.write(File.join(marker_dir, "#{worker_index}-#{i}-event-busy"), "1")
      end
    end

    conn.close
    exit!(0)
  rescue StandardError => e
    File.write(File.join(marker_dir, "#{worker_index}-exception"), "#{e.class}: #{e.message}")
    exit!(1)
  end
end
