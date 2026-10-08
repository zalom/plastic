# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkCompletionEvidenceTest < Plastic::TestCase
  Evidence = Plastic::Graph::Work::Completion::Evidence

  def setup
    super
    @intent = open_intent
  end

  def read(path, criteria = ["It works"]) = Evidence.new(folder, @intent).read(path, criteria)

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

  def refused(evidence, keys) = assert_raises(Plastic::Invalid) { Evidence.validate(evidence, keys) }.message

  def test_evidence_that_covers_every_key_is_returned
    assert_equal({ "a-key" => "yes" }, Evidence.validate({ "a-key" => "yes" }, ["a-key"]))
  end

  def test_evidence_by_text_for_a_keyed_criterion_names_the_missing_and_extra_key
    message = refused({ "The close works" => "yes" }, ["abandon-close"])

    assert_includes message, "missing keys: abandon-close"
    assert_includes message, "extra keys: The close works"
  end

  def test_a_refusal_names_the_missing_keys
    message = refused({ "one" => "yes" }, %w[one two three])

    assert_includes message, "missing keys: two, three"
    refute_includes message, "extra keys"
  end

  def test_a_refusal_names_the_extra_keys
    message = refused({ "one" => "yes", "stray" => "yes" }, ["one"])

    assert_includes message, "extra keys: stray"
    refute_includes message, "missing keys"
  end

  def test_a_refusal_names_the_keys_with_blank_text
    message = refused({ "one" => " ", "two" => "yes", "three" => 3 }, %w[one two three])

    assert_includes message, "blank keys: one, three"
  end

  def test_evidence_that_is_not_an_object_is_refused
    assert_equal "evidence must be a JSON object from criterion key to evidence text", refused(["one"], ["one"])
    assert_equal "evidence must be a JSON object from criterion key to evidence text", refused("one", ["one"])
  end
end
