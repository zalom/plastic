require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/doctor"

# Hermetic tests for doctor's read-only QMD check category (intent 45a).
# detector/runner are injected so no real `qmd` binary is involved.
class DoctorQmdTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-doctor-qmd")
    FileUtils.mkdir_p(File.join(@home, "store"))
    FileUtils.mkdir_p(File.join(@home, "projects", "dealintell", "store"))
    File.write(File.join(@home, "projects.yml"), <<~YML)
      projects:
        dealintell:
          path: "/Users/zlatko/apps/personal/dealintell"
          status: active
    YML
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def doctor
    Doctor.new(plastic_home: @home)
  end

  def present
    ->(*) { true }
  end

  def absent
    ->(*) { false }
  end

  # A runner returning a canned `collection list` listing.
  def runner_listing(collections)
    listed = collections.map { |c| "#{c} (qmd://#{c}/)" }.join("\n")
    lambda do |args|
      return [listed, true] if args[0] == "collection" && args[1] == "list"
      ["", true]
    end
  end

  def by_name(checks, name)
    checks.find { |c| c[:name] == name }
  end

  def test_absent_returns_single_pass
    checks = doctor.check_qmd(detector: absent, runner: runner_listing([]))

    assert_equal 1, checks.size
    only = checks.first
    assert_equal "qmd", only[:category]
    assert_equal "present", only[:name]
    assert_equal "pass", only[:status]
    assert_equal "QMD not installed (optional integration)", only[:message]
  end

  def test_present_with_missing_collections_warns
    # Only the global collection is registered; project store is missing.
    checks = doctor.check_qmd(detector: present, runner: runner_listing(["plastic-global"]))

    assert_equal "pass", by_name(checks, "present")[:status]

    collections = by_name(checks, "collections")
    assert_equal "warn", collections[:status]
    assert collections[:fixable]
    assert_equal "Run: qmd-sync register --all", collections[:fix_hint]
    assert_includes collections[:details], "plastic-dealintell"
  end

  def test_present_all_registered_passes
    listing = runner_listing(["plastic-global", "plastic-dealintell"])
    checks = doctor.check_qmd(detector: present, runner: listing)

    assert_equal "pass", by_name(checks, "present")[:status]

    collections = by_name(checks, "collections")
    assert_equal "pass", collections[:status]
    refute collections[:fixable]
  end

  def test_scoped_collection_pass_when_registered
    checks = doctor.check_qmd(detector: present,
      runner: runner_listing(["plastic-global", "plastic-dealintell"]),
      collection: "plastic-dealintell")

    collections = by_name(checks, "collections")
    assert_equal "pass", collections[:status]
    assert_includes collections[:message], "plastic-dealintell"
  end

  def test_scoped_collection_warns_naming_only_itself
    # plastic-global IS registered; plastic-dealintell is not. Scoped to
    # plastic-dealintell only, the warn must name only that one collection, not
    # every missing store in the install.
    checks = doctor.check_qmd(detector: present,
      runner: runner_listing(["plastic-global"]),
      collection: "plastic-dealintell")

    collections = by_name(checks, "collections")
    assert_equal "warn", collections[:status]
    assert_equal ["plastic-dealintell"], collections[:details]
  end

  def test_unscoped_default_behavior_is_unchanged
    # collection: not passed at all -> byte-for-byte pre-221 behavior.
    checks = doctor.check_qmd(detector: present, runner: runner_listing(["plastic-global"]))

    collections = by_name(checks, "collections")
    assert_equal "warn", collections[:status]
    assert_includes collections[:details], "plastic-dealintell"
  end
end
