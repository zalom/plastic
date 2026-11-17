# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeReaderLinkFileTest < Plastic::TestCase
  fixtures :alpha

  LinkFile = Plastic::Graph::Knowledge::Reader::LinkFile

  def index(links) = JSON.generate({ "intents" => [], "clusters" => [], "links" => links })

  def link(**fields) = { "from_ref" => "1", "to_ref" => "notes.md", "kind" => "source" }.merge(fields.transform_keys(&:to_s))

  def apply(links, replace: false) = store_graphs.databases.fetch(:store).transaction { |batch| LinkFile.new(index(links), origin, replace).apply(batch, FixedClock::STAMP) }

  def held = retrieval.links("1").map { |row| [row.to_ref, row.kind, row.at] }

  def test_a_link_with_no_time_takes_the_time_of_the_read
    apply([link])

    assert_equal [["notes.md", "source", FixedClock::STAMP]], held
  end

  def test_a_link_keeps_the_time_it_was_printed_with
    apply([link(at: "2026-01-01T00:00:00Z")])

    assert_equal [["notes.md", "source", "2026-01-01T00:00:00Z"]], held
  end

  def test_a_part_with_a_printed_row_replaces_the_links_of_this_home
    apply([link(to_ref: "old.md")])
    apply([link], replace: true)

    assert_equal ["notes.md"], held.map(&:first)
  end

  def test_a_part_with_no_printed_row_only_adds_links
    apply([link(to_ref: "old.md")])
    apply([link])

    assert_equal %w[notes.md old.md], held.map(&:first).sort
  end

  def test_a_link_with_a_kind_outside_the_known_kinds_is_refused
    error = assert_raises(Plastic::Invalid) { apply([link(kind: "mystery")]) }

    assert_includes error.message, "needs a from_ref, a to_ref and a kind of"
  end

  def test_a_link_with_no_end_is_refused
    assert_raises(Plastic::Invalid) { apply([link(to_ref: "")]) }
  end
end
