# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/resources/link_rewrite"

class ResourcesLinkRewriteTest < Plastic::TestCase
  LinkRewrite = Plastic::Graph::Knowledge::Resources::LinkRewrite

  DIR = "store/1--a"
  MOVES = {
    "#{DIR}/reviews/r1.md" => "#{DIR}/resources/output/reports/reviews/r1.md",
    "#{DIR}/references/ref.md" => "#{DIR}/resources/references/ref.md",
    "store/2--b/reviews/r2.md" => "store/2--b/resources/output/reports/reviews/r2.md"
  }.freeze
  KNOWN = (%w[spec.md reviews/r1.md references/ref.md].map { |rel| "#{DIR}/#{rel}" } + %w[store/2--b/spec.md store/2--b/reviews/r2.md]).freeze

  def rewrite(path, text) = LinkRewrite.new(MOVES, KNOWN).call("#{DIR}/#{path}", text)

  def test_rewrites_a_link_from_a_moved_file
    found = rewrite("reviews/r1.md", "[spec](../spec.md) <a href=\"../spec.md#top\">x</a>")

    assert_equal ["[spec](../../../../spec.md) <a href=\"../../../../spec.md#top\">x</a>", []], [found.text, found.unresolved]
  end

  def test_rewrites_a_link_to_a_moved_file
    found = rewrite("spec.md", "[review](reviews/r1.md) [ref](references/ref.md#a)")

    assert_equal "[review](resources/output/reports/reviews/r1.md) [ref](resources/references/ref.md#a)", found.text
  end

  def test_rewrites_a_link_between_two_moved_files
    found = rewrite("reviews/r1.md", "[ref](../references/ref.md)")

    assert_equal "[ref](../../../references/ref.md)", found.text
  end

  def test_leaves_an_absolute_or_web_link
    text = "[a](https://example.com/x.md) [b](/etc/hosts) [c](mailto:a@b.c) [d](#top) [e](?page=2)"
    found = rewrite("reviews/r1.md", text)

    assert_equal [text, []], [found.text, found.unresolved]
  end

  def test_leaves_a_link_that_did_not_resolve_before_and_names_it
    found = rewrite("reviews/r1.md", "[gone](missing.md) [out](../../../../elsewhere.md)")

    assert_equal ["[gone](missing.md) [out](../../../../elsewhere.md)", %w[missing.md ../../../../elsewhere.md]], [found.text, found.unresolved]
  end

  def test_a_link_out_of_the_intent_folder_is_recomputed_when_the_holder_moves
    found = rewrite("reviews/r1.md", "[other](../../2--b/spec.md#top)")

    assert_equal ["[other](../../../../../2--b/spec.md#top)", []], [found.text, found.unresolved]
  end

  def test_a_link_to_a_file_that_moves_in_another_intent_is_recomputed
    found = rewrite("spec.md", "[other](../2--b/reviews/r2.md)")

    assert_equal "[other](../2--b/resources/output/reports/reviews/r2.md)", found.text
  end

  def test_a_link_out_of_the_store_folder_is_unresolved
    found = rewrite("spec.md", "[up](../../../README.md)")

    assert_equal ["../../../README.md"], found.unresolved
  end
end
