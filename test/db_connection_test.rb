require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "sqlite3"

require_relative "../scripts/lib/db"

# Hermetic unit tests for Plastic::DB's connection core (intent 41, ACTION_1):
# write-discipline PRAGMAs, the with_write/retryable bounded-retry helper, and
# the store resolver (CWD-match default, global-on-cwd-miss). Everything runs
# against Dir.mktmpdir stores and DB paths, single process, no ENV/global seam.
class DbConnectionTest < Minitest::Test
  def setup
    @store_home = Dir.mktmpdir("plastic-db-store")
  end

  def teardown
    FileUtils.rm_rf(@store_home)
  end

  def test_connect_sets_write_discipline_pragmas
    conn = Plastic::DB.connect(@store_home)
    refute_nil conn

    assert_equal "wal", conn.pragma("journal_mode")
    assert_operator conn.pragma("busy_timeout"), :>=, 5000
    assert_equal 1, conn.pragma("synchronous")
    assert_equal 1, conn.pragma("foreign_keys")
  end

  def test_with_write_uses_begin_immediate_and_commits
    conn = Plastic::DB.connect(@store_home)
    refute_nil conn

    Plastic::DB.with_write(conn) do |c|
      c.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)")
      c.execute("INSERT INTO t (v) VALUES (?)", ["hello"])
    end

    fresh = Plastic::DB.connect(@store_home)
    assert_equal [["hello"]], fresh.execute("SELECT v FROM t")
  end

  # A connection stub whose `transaction` raises SQLite3::BusyException the
  # first `fail_times` calls, then yields (succeeds) on the next.
  class BusyStub
    attr_reader :attempts

    def initialize(fail_times:)
      @fail_times = fail_times
      @attempts = 0
    end

    def transaction(_mode)
      @attempts += 1
      raise SQLite3::BusyException, "database is locked" if @attempts <= @fail_times
      yield
    end
  end

  def test_with_write_retries_on_busy_then_succeeds
    stub = BusyStub.new(fail_times: 2)
    sleeps = []
    sleeper = ->(secs) { sleeps << secs }

    result = Plastic::DB.with_write(stub, tries: 5, base_sleep: 0.01, sleeper: sleeper) { |_c| :written }

    assert_equal :written, result
    assert_equal 3, stub.attempts
    assert_equal 2, sleeps.length
  end

  def test_with_write_gives_up_after_bounded_retries
    stub = BusyStub.new(fail_times: 999)
    sleeper = ->(_secs) {}

    result = Plastic::DB.with_write(stub, tries: 5, base_sleep: 0.01, sleeper: sleeper) { |_c| :written }

    assert_nil result
    assert_equal 5, stub.attempts
  end

  def test_connect_fails_open_when_gem_absent
    conn = Plastic::DB.connect(@store_home, available: false)
    assert_nil conn
    assert_nil Plastic::DB.with_write(conn) { |_c| :never }
  end

  def test_connect_fails_open_on_unopenable_path
    # store_home is a plain file, not a directory: File.join(store_home, "plastic.db")
    # is unopenable, so connect must fail open instead of raising.
    file_path = File.join(@store_home, "not_a_dir")
    File.write(file_path, "x")

    conn = Plastic::DB.connect(file_path)
    assert_nil conn
  end

  def test_resolver_cwd_match_default
    plastic_home = Dir.mktmpdir("plastic-home")
    project_root = Dir.mktmpdir("project-p")
    FileUtils.mkdir_p(File.join(plastic_home, "projects", "p"))
    File.write(File.join(plastic_home, "projects.yml"), <<~YML)
      projects:
        p:
          path: "#{project_root}"
    YML

    resolved = Plastic::DB::StoreResolver.resolve(
      cwd: File.join(project_root, "subdir"), plastic_home: plastic_home
    )

    assert_equal "p", resolved[:slug]
    assert_equal File.join(plastic_home, "projects", "p"), resolved[:store_home]
    assert_equal File.join(plastic_home, "projects", "p", "plastic.db"), resolved[:db_path]
  ensure
    FileUtils.rm_rf(plastic_home)
    FileUtils.rm_rf(project_root)
  end

  def test_resolver_global_on_cwd_miss
    plastic_home = Dir.mktmpdir("plastic-home")
    unrelated_cwd = Dir.mktmpdir("nowhere")
    File.write(File.join(plastic_home, "projects.yml"), <<~YML)
      projects:
        p:
          path: "/somewhere/else/entirely"
    YML

    resolved = Plastic::DB::StoreResolver.resolve(cwd: unrelated_cwd, plastic_home: plastic_home)

    assert_nil resolved[:slug]
    assert_equal plastic_home, resolved[:store_home]
    assert_equal File.join(plastic_home, "plastic.db"), resolved[:db_path]
  ensure
    FileUtils.rm_rf(plastic_home)
    FileUtils.rm_rf(unrelated_cwd)
  end
end
