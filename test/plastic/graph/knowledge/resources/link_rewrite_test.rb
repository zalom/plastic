# frozen_string_literal: true

require_relative "../../../../test_helper"

class ResourcesLinkRewriteTest < Plastic::TestCase
  LinkRewrite = Plastic::Graph::Knowledge::Resources::LinkRewrite

  MOVES = { "reviews/r1.md" => "resources/output/reports/reviews/r1.md", "references/ref.md" => "resources/references/ref.md" }.freeze
  KNOWN = %w[spec.md reviews/r1.md references/ref.md].freeze

  def rewrite(path, text) = LinkRewrite.new(MOVES, KNOWN).call(path, text)

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
    text = "[a](https://example.com/x.md) [b](/etc/hosts) [c](mailto:a@b.c) [d](#top)"
    found = rewrite("reviews/r1.md", text)

    assert_equal [text, []], [found.text, found.unresolved]
  end

  def test_leaves_a_link_that_did_not_resolve_before_and_names_it
    found = rewrite("reviews/r1.md", "[gone](missing.md) [out](../../elsewhere.md)")

    assert_equal ["[gone](missing.md) [out](../../elsewhere.md)", %w[missing.md ../../elsewhere.md]], [found.text, found.unresolved]
  end
end
