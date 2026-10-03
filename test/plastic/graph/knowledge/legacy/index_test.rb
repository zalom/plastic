# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLegacyIndexTest < Plastic::TestCase
  LegacyIndex = Plastic::Graph::Knowledge::Legacy::Index

  TEXT = <<~MARKDOWN
    # Index

    ## Active
    - [396 — Stage 2 storage](store/396--trigraph-storage/396--trigraph-storage.md)

    ## Future
    - [380 - Plastic's license](store/380--license/380--license.md) - 2026-09-22 owner ask

    ## Clusters

    ### Core Design
    - [1 — Design](store/1--design/1--design.md) _(completed)_
    - [380 - Plastic's license](store/380--license/380--license.md)

    ## Abandoned
    - [307a — Auto shape](store/307a--auto-shape/307a--auto-shape.md) — 2026-08-31 abandoned without work

    ## Completed
    - [394 — Land the kernel](store/394--trigraph-kernel/394--trigraph-kernel.md) — 2026-10-01

    ## Relocated
    - `1b1a1 → 41` (data & search layer)
  MARKDOWN

  def entries = LegacyIndex.parse(TEXT).entries.to_h { |entry| [entry.intent_id, entry] }

  def test_each_section_gives_its_status_and_line_detail
    found = entries

    assert_equal %w[active future done abandoned done], %w[396 380 1 307a 394].map { |id| found.fetch(id).status }
    assert_equal [[nil, "2026-09-22 owner ask"], ["2026-08-31", "abandoned without work"], ["2026-10-01", nil]],
      %w[380 307a 394].map { |id| found.fetch(id).to_h.values_at(:closed_at, :disposition) }
  end

  def test_an_entry_names_its_folder
    assert_equal "store/396--trigraph-storage", entries.fetch("396").dir
  end

  def test_clusters_keep_their_names_and_intents
    assert_equal [%w[Core\ Design 1], %w[Core\ Design 380]], LegacyIndex.parse(TEXT).clusters.map { |c| [c.name, c.intent_id] }
  end

  def test_an_entry_and_a_folder_must_match
    parsed = LegacyIndex.parse(TEXT)
    error = assert_raises(Plastic::Invalid) { parsed.check(%w[store/396--trigraph-storage store/9--stray]) }

    assert_includes error.message, "store/9--stray has no entry in INDEX.md"
    assert_includes error.message, "store/394--trigraph-kernel is in INDEX.md and has no folder"
  end

  def test_an_intent_listed_in_two_status_sections_is_refused
    error = assert_raises(Plastic::Invalid) { LegacyIndex.parse("## Active\n#{TEXT.lines[3]}\n## Future\n#{TEXT.lines[3]}") }

    assert_includes error.message, "396 is listed twice"
  end

  def test_a_link_under_an_unknown_section_is_refused
    error = assert_raises(Plastic::Invalid) { LegacyIndex.parse("## Someday\n#{TEXT.lines[3]}") }

    assert_includes error.message, "Someday"
  end

  def test_an_entry_imports_as_an_intent_row
    row = entries.fetch("307a").row({ "kind" => "research", "created" => "2026-08-01" }, "now")

    assert_equal({ intent_id: "307a", parent_id: "307", slug: "auto-shape", title: "Auto shape", kind: "research",
                   status: "abandoned", disposition: "abandoned without work", opened_at: "2026-08-01",
                   closed_at: "2026-08-31", updated_at: "now" }, row)
  end

  def test_the_counts_name_the_intents_and_the_clusters
    assert_equal({ "intents" => 5, "clusters" => 2 }, LegacyIndex.parse(TEXT).counts)
  end

  def test_a_slug_keeps_every_double_dash_after_the_id
    assert_equal "a--b", LegacyIndex::Entry.new("9", "T", "store/9--a--b", "open", nil, nil).row({}, "now")[:slug]
  end

  def test_an_intent_marked_only_in_a_cluster_has_no_closing
    assert_equal ["done", nil, nil], entries.fetch("1").to_h.values_at(:status, :disposition, :closed_at)
  end

  def test_a_dash_with_no_space_still_opens_the_detail
    entry = LegacyIndex.parse("## Completed\n- [4 — Four](store/4--four/4--four.md) —2026-10-01 shipped\n").entries.first

    assert_equal %w[2026-10-01 shipped], entry.to_h.values_at(:closed_at, :disposition)
  end

  def test_every_problem_is_named_in_one_message
    error = assert_raises(Plastic::Invalid) { LegacyIndex.parse("## Someday\n#{TEXT.lines[3]}## Later\n#{TEXT.lines[6]}") }

    assert_equal "INDEX.md: 396 sits under ## Someday, which gives no status; 380 sits under ## Later, which gives no status", error.message
  end

  def test_a_check_names_every_missing_entry_and_folder
    error = assert_raises(Plastic::Invalid) { LegacyIndex.parse(TEXT).check(%w[store/9--stray]) }

    assert_match(/\Astore\/9--stray has no entry in INDEX.md; store\/396--trigraph-storage is in INDEX.md and has no folder; /, error.message)
  end
end
