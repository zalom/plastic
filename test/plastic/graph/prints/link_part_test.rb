# frozen_string_literal: true

require_relative "../../../test_helper"

class PrintsLinkPartTest < Plastic::TestCase
  LinkPart = Plastic::Graph::Prints::LinkPart

  def digest(data) = LinkPart.file_digest(JSON.generate(data))

  def test_a_file_that_is_no_json_has_no_digest
    assert_nil LinkPart.file_digest("{ not json")
  end

  def test_a_file_with_no_links_key_has_no_digest
    assert_nil digest("clusters" => [])
  end

  def test_the_time_a_link_was_made_changes_no_digest
    link = { "from_ref" => "1", "to_ref" => "2", "kind" => "chain" }

    assert_equal digest("links" => [link]), digest("links" => [link.merge("created_at" => "2026-11-15T10:00:00Z")])
  end

  def test_links_listed_as_no_list_have_a_digest_of_their_own
    refute_equal digest("links" => []), digest("links" => "chain")
  end

  def test_a_link_listed_as_no_object_keeps_its_place_in_the_digest
    refute_equal digest("links" => [%w[1 2 chain]]), digest("links" => [%w[1 3 chain]])
  end
end
