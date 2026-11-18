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
end
