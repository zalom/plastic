# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderTextFileTest < Plastic::TestCase
  Subject = Plastic::Graph::Knowledge::Reader::TextFile::Subject

  def test_the_legacy_row_holds_the_text_under_its_path
    subject = Subject.new("1", "plan.md", "body", "t")

    assert_equal({ intent_id: "1", path: "plan.md", body: "body", updated_at: "t" }, subject.legacy_row)
  end

  def test_the_document_carries_the_path_and_the_text
    document = Subject.new("1", "spec.md", "body", "t").document

    assert_equal ["1", "spec.md", "body"], [document.intent_id, document.path, document.body]
  end

  def test_the_subject_names_itself_to_a_removal
    removal = Struct.new(:args) { def remove(*given) = self.args = given }.new

    Subject.new("1", "plan.md", "body", "t").removed_by(removal)

    assert_equal ["1", "plan.md"], removal.args
  end
end
