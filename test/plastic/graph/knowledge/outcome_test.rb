# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeOutcomeTest < Plastic::TestCase
  Outcome = Plastic::Graph::Knowledge::Outcome

  def setup
    super
    @intent = open_intent
  end

  def outcome(body)
    write("#{@intent.dir}/outcome.md", body)
    sync_up
    Outcome.new(retrieval, "1")
  end

  def records(body)
    read = outcome(body)
    [read.merged?, read.architecture_map?]
  end

  def test_both_labels_under_verification_count
    assert_equal [true, true], records("# Outcome\n\n## Verification\n- Merged: branch into alpha at abc\n- Architecture map: enola at abc\n")
  end

  def test_a_merge_line_outside_verification_does_not_count
    assert_equal [false, false], records("# Outcome\n\n- Merged: branch into alpha at abc\n\n## Verification\n- Tests pass\n\n## Notes\n- Architecture map: enola\n")
  end

  def test_a_label_with_no_text_does_not_count
    assert_equal [false, false], records("## Verification\n- Merged:\n- Architecture map:   \n")
  end

  def test_labels_match_with_a_checkbox_and_any_case
    assert_equal [true, true], records("## Verification\n- [x] merged: branch\n- [ ] ARCHITECTURE MAP: enola\n")
  end

  def test_no_outcome_records_neither
    read = Outcome.new(retrieval, "1")

    assert_equal [false, false], [read.merged?, read.architecture_map?]
  end

  def test_a_bold_label_counts
    assert_equal [true, true], records("## Verification\n- **Merged:** branch\n- **Architecture map**: enola\n")
  end

  def test_a_star_bullet_counts
    assert_equal [true, false], records("## Verification\n* Merged: branch\n")
  end

  def test_bullets_under_a_subheading_of_verification_count
    assert_equal [true, true], records("## Verification\n### Merge\n- Merged: branch\n### Map\n- Architecture map: enola\n")
  end

  def test_a_third_level_verification_heading_counts
    assert_equal [true, false], records("### Verification\n- Merged: branch\n#### Detail\n- other\n## Next\n- Architecture map: enola\n")
  end
end
