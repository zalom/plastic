# frozen_string_literal: true

require_relative "../../../../test_helper"

class PrintsClusterPartTest < Plastic::TestCase
  ClusterPart = Plastic::Graph::Prints::ClusterPart

  def digest(data) = ClusterPart.file_digest(JSON.generate(data))

  def test_a_file_that_is_no_json_has_no_digest
    assert_nil ClusterPart.file_digest("{ not json")
  end

  def test_a_file_with_no_clusters_key_has_no_digest
    assert_nil digest("links" => [])
  end

  def test_the_same_clusters_in_any_order_have_one_digest
    one = { "name" => "a", "intents" => %w[1 2] }
    two = { "name" => "b", "intents" => %w[3] }

    assert_equal digest("clusters" => [one, two]), digest("clusters" => [two, one.merge("intents" => %w[2 1])])
  end

  def test_clusters_listed_as_no_list_of_objects_have_a_digest_of_their_own
    refute_equal digest("clusters" => []), digest("clusters" => ["a"])
  end
end
