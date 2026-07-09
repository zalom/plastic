# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/doctor"
require_relative "../scripts/lib/db"

# Doctor's database category (intent 41 ACTION_12): sqlite3 gem presence
# (advisory), per-store plastic.db health (open + schema format_version
# current), and a leftover-/tmp-bridge report. Every check here must stay
# read-only and must never force-create a plastic.db for a store that has
# none yet (D3: lazy provisioning). Hermetic Dir.mktmpdir homes throughout.
class DoctorDatabaseTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-doctor-db")
    FileUtils.mkdir_p(File.join(@home, "store"))
    File.write(File.join(@home, "INDEX.md"), "# Index\n\n## Active\n\n## Future\n\n## Clusters\n\n## Abandoned\n\n## Completed\n")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  # A fake, nonexistent agent dir so run_checks stays hermetic (no reads
  # against the real ~/.claude): check_agent_registration handles a missing
  # agent_dir gracefully (one "fail" check), never raises.
  def doctor
    Doctor.new(plastic_home: @home,
               agents: { "claude" => { name: "Claude Code", dir: File.join(@home, "no-such-agent-dir") } })
  end

  def check(name, available: true, tmp_dir: "/nonexistent-plastic-doctor-tmp")
    doctor.check_database(available: available, tmp_dir: tmp_dir).find { |c| c[:name] == name }
  end

  # --- sqlite3_gem -----------------------------------------------------

  def test_sqlite3_gem_pass_when_available
    assert_equal "pass", check("sqlite3_gem", available: true)[:status]
  end

  def test_sqlite3_gem_warn_when_unavailable_with_fix_hint
    result = check("sqlite3_gem", available: false)
    assert_equal "warn", result[:status]
    assert result[:fixable]
    assert_match(/gem install sqlite3/, result[:fix_hint])
  end

  # --- db_health ---------------------------------------------------------

  def test_db_health_pass_when_no_store_has_been_provisioned_yet
    result = check("db_health", available: true)
    assert_equal "pass", result[:status]
    assert_match(/no plastic\.db provisioned/i, result[:message])
  end

  def test_db_health_skips_when_sqlite3_unavailable
    result = check("db_health", available: false)
    assert_equal "pass", result[:status]
    assert_match(/skipped/i, result[:message])
  end

  def test_db_health_pass_for_a_provisioned_healthy_store
    Plastic::DB.connect(@home) # provisions plastic.db + runs Schema.ensure!

    result = check("db_health", available: true)
    assert_equal "pass", result[:status]
    assert_match(/1 provisioned/, result[:message])
  end

  def test_db_health_warns_on_stale_format_version
    conn = Plastic::DB.connect(@home)
    conn.execute("UPDATE schema_meta SET format_version = 0 WHERE id = 1")

    result = check("db_health", available: true)
    assert_equal "warn", result[:status]
    assert result[:fixable]
    assert(result[:details].any? { |d| d.include?("stale") })
  end

  def test_db_health_never_creates_a_db_for_an_unprovisioned_store
    check("db_health", available: true)
    refute File.exist?(File.join(@home, "plastic.db")),
           "doctor must never force-create plastic.db just by checking health"
  end

  # --- stale_bridges -------------------------------------------------------

  def test_stale_bridges_pass_when_none_found
    Dir.mktmpdir("doctor-tmp-empty") do |tmp|
      result = check("stale_bridges", tmp_dir: tmp)
      assert_equal "pass", result[:status]
    end
  end

  def test_stale_bridges_warns_but_never_fails_when_leftovers_exist
    Dir.mktmpdir("doctor-tmp-stale") do |tmp|
      File.write(File.join(tmp, "plastic-old-session.json"), "{}")
      result = check("stale_bridges", tmp_dir: tmp)
      assert_equal "warn", result[:status]
      assert result[:fixable]
      assert(result[:details].any? { |d| d.include?("plastic-old-session.json") })
    end
  end

  # --- wired into the full run -------------------------------------------

  def test_check_database_is_part_of_run_checks
    names = doctor.run_checks("claude")[:checks].map { |c| c[:name] }
    assert_includes names, "sqlite3_gem"
    assert_includes names, "db_health"
    assert_includes names, "stale_bridges"
  end
end
