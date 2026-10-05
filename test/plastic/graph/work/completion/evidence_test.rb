# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkCompletionEvidenceTest < Plastic::TestCase
  Evidence = Plastic::Graph::Work::Completion::Evidence

  def setup
    super
    @intent = open_intent
  end

  def read(path, criteria = ["It works"]) = Evidence.read(folder, @intent, path, criteria)

  def refusal(path) = assert_raises(Plastic::Invalid) { read(path) }.message

  def test_evidence_inside_the_intent_maps_each_criterion_to_its_text
    write("#{@intent.dir}/completion.json", '{"It works":"the tests pass"}')

    assert_equal({ "It works" => "the tests pass" }, read("completion.json"))
  end

  def test_a_path_outside_the_intent_is_refused
    assert_equal "evidence must be a file inside intent 1", refusal("../outside.json")
  end

  def test_a_link_that_leaves_the_intent_is_refused
    write("store/outside.json", "{}")
    File.symlink(store_path("store/outside.json"), store_path("#{@intent.dir}/link.json"))

    assert_equal "evidence must stay inside intent 1", refusal("link.json")
  end

  def test_a_missing_file_is_refused_with_the_reason
    assert_match(/\Acannot read criterion evidence: No such file or directory/, refusal("missing.json"))
  end

  def test_a_file_that_is_not_json_is_refused
    write("#{@intent.dir}/completion.json", "not json")

    assert_match(/\Acannot read criterion evidence: /, refusal("completion.json"))
  end

  def test_evidence_that_misses_a_criterion_is_refused
    error = assert_raises(Plastic::Invalid) { Evidence.validate({ "It works" => "yes" }, ["It works", "It ships"]) }

    assert_equal "evidence must map every exact done criterion to nonempty evidence text", error.message
  end

  def test_evidence_with_blank_text_is_refused
    assert_raises(Plastic::Invalid) { Evidence.validate({ "It works" => " " }, ["It works"]) }
  end
end
