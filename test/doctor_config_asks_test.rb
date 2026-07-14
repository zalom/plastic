require "minitest/autorun"
require "tmpdir"
require "yaml"
require "fileutils"

require_relative "../scripts/doctor"
require_relative "doctor_test" # reuse DoctorTestHelpers + DOCTOR_TEST_* constants

# check_config_asks (intent 194): reads config_asks.yml via ConfigAsks and
# rolls up into one pass/warn check, mirroring check_deprecations's shape.
#
# Orchestrator amendment 1 (this intent): wired into run_checks (the FULL
# tier) ONLY, deliberately excluded from run_core_checks (the fast/binary
# tier run_post_update_doctor defaults to). See doctor.rb's check_config_asks
# docstring for why: a warn in the binary core tier flips the whole result to
# "fail" on every post-update doctor run until the question is answered,
# re-noising the exact surface intent 126 quieted. This file proves both the
# check's own pass/warn behavior and the tier placement.
class DoctorConfigAsksTest < Minitest::Test
  include DoctorTestHelpers

  def setup
    FileUtils.rm_rf([DOCTOR_TEST_HOME, DOCTOR_TEST_CLAUDE])
    FileUtils.mkdir_p(DOCTOR_TEST_HOME)
    FileUtils.mkdir_p(DOCTOR_TEST_CLAUDE)
  end

  def teardown
    FileUtils.rm_rf([DOCTOR_TEST_HOME, DOCTOR_TEST_CLAUDE])
  end

  def write_manifest(entries = [sample_entry])
    File.write(File.join(DOCTOR_TEST_HOME, "config_asks.yml"), YAML.dump("config_asks" => entries))
  end

  def write_global_config(data)
    File.write(File.join(DOCTOR_TEST_HOME, "config.yml"), YAML.dump(data))
  end

  def sample_entry
    {
      "id" => "advisor-default",
      "key" => "advisor.claude.default",
      "introduced" => "1.3.0",
      "question" => "Which advisor should be the default?",
      "options" => [
        { "label" => "Faux Fable", "value" => "plastic-faux-advisor" },
        { "label" => "Fable 5", "value" => "plastic-advisor" },
      ],
    }
  end

  def test_pass_when_no_manifest
    # No config_asks.yml in the tmp home at all.
    checks = doctor.check_config_asks

    assert_equal 1, checks.size
    assert_equal "pass", checks.first[:status]
    assert_equal "config_asks", checks.first[:category]
  end

  def test_warn_when_entry_pending
    write_manifest
    # No config.yml -- key is unset.

    checks = doctor.check_config_asks
    check = checks.first

    assert_equal "warn", check[:status]
    assert check[:details].any? { |d| d.include?("Which advisor should be the default?") },
      "expected the question text in details, got: #{check[:details].inspect}"
    assert check[:details].any? { |d| d.include?("write-config") },
      "expected a write-config command line in details, got: #{check[:details].inspect}"
  end

  def test_pass_when_key_already_set
    write_manifest
    write_global_config("advisor" => { "claude" => { "default" => "plastic-advisor" } })

    checks = doctor.check_config_asks
    assert_equal "pass", checks.first[:status]
  end

  def test_pass_when_dismissed
    write_manifest
    write_global_config("config_asks_dismissed" => ["advisor-default"])

    checks = doctor.check_config_asks
    assert_equal "pass", checks.first[:status]
  end

  # --- Amendment 1 tier guard: full-only, never core ---

  def test_config_asks_absent_from_run_core_checks_present_in_run_checks
    write_manifest
    # Key unset -> pending, so check_config_asks alone would warn if reached.

    core_names = doctor.run_core_checks("claude")[:checks].map { |c| c[:name] }
    core_categories = doctor.run_core_checks("claude")[:checks].map { |c| c[:category] }
    full_categories = doctor.run_checks("claude")[:checks].map { |c| c[:category] }

    refute_includes core_categories, "config_asks",
      "config_asks must NOT run in the fast/core tier (run_post_update_doctor defaults to it, " \
      "and any warn there flips the binary result to fail on every healthy install)"
    assert_includes full_categories, "config_asks",
      "config_asks must run in the full tier (run_checks)"
  end
end
