# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/project_links"

class ProjectLinksTest < Plastic::TestCase
  def links = plastic("project", "links", table: Plastic::CLI::TABLE)

  def link(from, to, kind = "cites")
    store_graphs.databases.fetch(:knowledge).transaction do |batch|
      batch.put(:links, { from_ref: from, to_ref: to, kind:, at: STAMP }, statement: :insert)
    end
  end

  def test_a_link_to_a_missing_intent_is_listed_and_fails_with_the_count
    open_intent
    link("1", "9")
    result = links

    assert_equal 1, result.code
    assert_includes result.out.lines.map(&:strip), "1 cites 9"
    assert_match(/1 link/, result.err)
  end

  def test_a_link_to_a_missing_ruling_is_listed
    open_intent
    link("1", "1/D7")

    assert_includes links.out.lines.map(&:strip), "1 cites 1/D7"
  end

  def test_links_that_all_resolve_exit_zero
    open_intent
    open_intent("Beta")
    link("1", "2")

    assert_equal [0, ""], [links.code, links.err]
  end

  def test_a_reference_into_another_store_is_not_checked
    open_intent
    link("1", "other:5")

    assert_equal 0, links.code
  end
end
