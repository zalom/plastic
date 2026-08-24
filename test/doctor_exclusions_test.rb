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

  # --- inline comments (review F3): docs say comments are ignored, so a trailing "# ..." on
  # an otherwise well-formed rule line must not drop the whole line, just the comment.

  def test_inline_trailing_comment_on_a_rule_line_is_stripped
    result = DoctorExclusions.parse("savepoint_operational 1 1a  # why\n")
    assert_equal({ "savepoint_operational" => ["1", "1a"] }, result[:rules])
    assert_empty result[:errors]
  end

  def test_hash_glued_to_a_token_with_no_preceding_whitespace_is_not_treated_as_a_comment
    # "1#stray" has no whitespace before "#", so it stays one token and correctly fails the
    # Folgezettel check, rather than being silently truncated to a bare "1".
    result = DoctorExclusions.parse("savepoint_operational 1#stray\n")
    assert_empty result[:rules]
    assert_equal 1, result[:errors].size
    assert_match(/"1#stray" is not a Folgezettel intent id/, result[:errors].first)
  end

  # --- invalid byte sequences (review F1): a hand-edited file can carry a byte invalid in
  # its declared encoding. String#strip/split/=~ all raise Encoding::CompatibilityError on
  # that input; load/parse must never raise (D5's never-raises contract covers every input,
  # not just well-formed UTF-8). Reproduced first against pre-fix code (raised
  # Encoding::CompatibilityError at doctor_exclusions.rb:44's String#strip), fixed via scrub.

  def test_load_never_raises_on_an_invalid_byte_in_a_comment_line
    path = File.join(@home, "doctor-exclusions")
    File.binwrite(path, "# a comment with a bad byte caf\xE9\nsavepoint_operational 1\n")

    result = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_equal({ "savepoint_operational" => ["1"] }, result[:rules])
    assert_empty result[:errors]
  end

  def test_load_never_raises_on_an_invalid_byte_in_a_rule_line
    path = File.join(@home, "doctor-exclusions")
    File.binwrite(path, "savepoint_operational 1\xFF\n")

    result = DoctorExclusions.load(File.join(@home, "INDEX.md"))
    assert_empty result[:rules]
    assert_equal 1, result[:errors].size
    assert_match(/is not a Folgezettel intent id/, result[:errors].first)
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

  # --- dead_rows (pure, intent 280) ---
  #
  # `loaded` is built by hand rather than via `parse` in the per-rule case: EXCLUDABLE_CHECKS
  # stays `savepoint_operational`-only in v1 (spec Non-Goals), so `parse` would reject a second
  # rule name outright. `dead_rows` itself is rule-generic by construction and does not care.

  def test_dead_rows_is_empty_when_every_registered_id_is_consumed
    loaded = DoctorExclusions.parse("savepoint_operational 1 2\n")
    result = DoctorExclusions.dead_rows(loaded, consumed: { "savepoint_operational" => ["1", "2"] },
                                                 known_ids: ["1", "2"])
    assert_empty result
  end

  def test_dead_rows_reports_no_finding_for_a_known_id_that_consumed_nothing
    loaded = DoctorExclusions.parse("savepoint_operational 1\n")
    result = DoctorExclusions.dead_rows(loaded, consumed: {}, known_ids: ["1"])
    assert_equal [{ rule: "savepoint_operational", id: "1", reason: :no_finding }], result
  end

  def test_dead_rows_reports_no_intent_for_an_id_that_names_no_walked_directory
    loaded = DoctorExclusions.parse("savepoint_operational 1\n")
    result = DoctorExclusions.dead_rows(loaded, consumed: {}, known_ids: [])
    assert_equal [{ rule: "savepoint_operational", id: "1", reason: :no_intent }], result
  end

  def test_dead_rows_is_per_rule
    loaded = { rules: { "savepoint_operational" => ["1"], "hooks_registered" => ["1"] }, errors: [] }
    result = DoctorExclusions.dead_rows(
      loaded, consumed: { "savepoint_operational" => ["1"] }, known_ids: ["1"]
    )
    assert_equal [{ rule: "hooks_registered", id: "1", reason: :no_finding }], result
  end

  def test_dead_rows_never_raises_on_empty_inputs
    loaded = { rules: {}, errors: [] }
    assert_equal [], DoctorExclusions.dead_rows(loaded)
  end
end
