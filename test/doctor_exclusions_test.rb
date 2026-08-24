# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/doctor_exclusions"

# Intent 274: DoctorExclusions is the per-store doctor-exclusions loader - a pure parser
# (`parse`) plus a thin, dependency-free IO wrapper (`load`) that never raises. Hermetic:
# every IO case uses a real tmpdir file, no eval, no ENV/global-constant seam.
class DoctorExclusionsTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("plastic-doctor-exclusions")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  # --- parse (pure) ---

  def test_well_formed_file_parses_into_expected_rules_with_zero_errors
    result = DoctorExclusions.parse("savepoint_operational 1 1a 1a2\n")
    assert_equal({ "savepoint_operational" => ["1", "1a", "1a2"] }, result[:rules])
    assert_empty result[:errors]
  end

  def test_blank_lines_and_comment_lines_are_ignored
    text = "\n# a comment\nsavepoint_operational 1\n   \n# another comment\n"
    result = DoctorExclusions.parse(text)
    assert_equal({ "savepoint_operational" => ["1"] }, result[:rules])
    assert_empty result[:errors]
  end

  # FALSIFIABLE (208): an unknown rule name yields one error naming the line number and
  # excludes nothing.
  def test_unknown_rule_name_yields_one_error_and_excludes_nothing
    result = DoctorExclusions.parse("not_a_real_rule 1\n")
    assert_equal 1, result[:errors].size
    assert_match(/line 1:.*unknown or non-excludable rule "not_a_real_rule"/, result[:errors].first)
    assert_empty result[:rules]
  end

  # FALSIFIABLE (208): a rule line with no ids yields one error and excludes nothing.
  def test_rule_line_with_no_ids_yields_one_error_and_excludes_nothing
    result = DoctorExclusions.parse("savepoint_operational\n")
    assert_equal 1, result[:errors].size
    assert_match(/line 1: rule "savepoint_operational" lists no intent ids/, result[:errors].first)
    assert_empty result[:rules]
  end

  # FALSIFIABLE (208): a non-Folgezettel id token invalidates the WHOLE line, excluding
  # nothing from it, even if other tokens on the same line are valid ids.
  def test_non_folgezettel_id_token_yields_one_error_and_excludes_the_whole_line
    result = DoctorExclusions.parse("savepoint_operational 1 not-an-id 2\n")
    assert_equal 1, result[:errors].size
    assert_match(/line 1: "not-an-id" is not a Folgezettel intent id/, result[:errors].first)
    assert_empty result[:rules]
  end

  def test_duplicate_rule_lines_union_their_ids_without_an_error
    text = "savepoint_operational 1 2\nsavepoint_operational 2 3\n"
    result = DoctorExclusions.parse(text)
    assert_equal ["1", "2", "3"], result[:rules]["savepoint_operational"].sort
    assert_empty result[:errors]
  end

  # --- load (IO) ---

  def test_missing_file_yields_empty_rules_and_empty_errors
    result = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_empty result[:rules]
    assert_empty result[:errors]
    assert_equal File.join(@home, "doctor-exclusions"), result[:path]
  end

  def test_load_parses_a_real_file_next_to_index
    File.write(File.join(@home, "doctor-exclusions"), "savepoint_operational 1\n")
    result = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_equal({ "savepoint_operational" => ["1"] }, result[:rules])
    assert_empty result[:errors]
  end

  def test_load_never_raises_on_an_unreadable_file
    path = File.join(@home, "doctor-exclusions")
    File.write(path, "savepoint_operational 1\n")
    File.chmod(0o000, path)

    result = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_empty result[:rules]
    refute_empty result[:errors]
    assert_match(/unreadable/, result[:errors].first)
  ensure
    File.chmod(0o644, path) if path && File.exist?(path)
  end

  # --- rules_for ---

  def test_rules_for_returns_empty_for_unlisted_id_and_the_rule_for_a_listed_one
    loaded = DoctorExclusions.parse("savepoint_operational 1\n")
    assert_equal [], DoctorExclusions.rules_for(loaded, "2")
    assert_equal ["savepoint_operational"], DoctorExclusions.rules_for(loaded, "1")
  end

  # --- path_for ---

  def test_path_for_resolves_next_to_a_global_shaped_index
    assert_equal File.join(@home, "doctor-exclusions"),
      DoctorExclusions.path_for(File.join(@home, "INDEX.md"))
  end

  def test_path_for_resolves_next_to_a_project_shaped_index
    project_index = File.join(@home, "projects", "plastic", "INDEX.md")
    assert_equal File.join(@home, "projects", "plastic", "doctor-exclusions"),
      DoctorExclusions.path_for(project_index)
  end
end
