# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeOutcomeFormTest < Plastic::TestCase
  Form = Plastic::Graph::Knowledge::OutcomeForm

  def test_a_merge_names_its_branch_and_its_commit
    assert_equal [true, false], [Form.in_form?("Merged", "alpha into main at 4f2a9c1"), Form.in_form?("Merged", "pending at PR #57")]
  end

  def test_an_approval_names_a_person_and_a_date
    assert_equal [true, false], [Form.in_form?("Approved", "Jev on 2026-11-14"), Form.in_form?("Approved", "<person> on <YYYY-MM-DD>")]
  end

  def test_the_form_shown_for_a_label_is_its_template
    assert_equal "Approved: <person> on <YYYY-MM-DD>", Form.shown("Approved")
  end

  def test_a_direct_commit_names_its_branch_and_a_commit_of_seven_to_forty_hex_characters
    values = ["main at 4f2a9c1", "main at `4f2a9c1`", "main at 4f2a9c", "main at PR #57", "not yet at 4f2a9c1", "<branch> at <commit>"]

    assert_equal [true, true, false, false, false, false], values.map { |value| Form.in_form?("Committed", value) }
  end

  def test_delivered_files_name_a_path_under_resources_output_and_a_reason
    values = ["resources/output/files/resume.pdf because the resume lives outside version control",
      "`resources/output/files` because the files are not code", "resources/output/files/resume.pdf",
      "resume.pdf because it is a document", "n/a resources/output/files/x because y", "resources/output/<path> because <reason>"]

    assert_equal [true, true, false, false, false, false], values.map { |value| Form.in_form?("Delivered", value) }
  end

  def test_the_forms_shown_for_a_commit_and_delivered_files_are_their_templates
    assert_equal ["Committed: <branch> at <commit>", "Delivered: resources/output/<path> because <reason>"], [Form.shown("Committed"), Form.shown("Delivered")]
  end

  def test_the_path_of_delivered_files_is_read_without_its_code_marks
    assert_equal ["resources/output/files", "resources/output/files/a.pdf"],
      [Form.delivered_path("`resources/output/files` because x"), Form.delivered_path("resources/output/files/a.pdf because x")]
  end
end
