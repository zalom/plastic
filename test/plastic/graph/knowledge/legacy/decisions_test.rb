# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLegacyDecisionsTest < Plastic::TestCase
  DIR = "store/4--alpha"

  def decisions = Plastic::Graph::Knowledge::Legacy::Decisions.new

  def read(originals) = decisions.read_decisions([DIR], originals).first

  def test_rulings_keep_their_numbers_and_take_the_next_free_one_otherwise
    assert_equal [["D3", "D3 Ship it"], ["D4", "Unnumbered"], ["D5", "**D3** again"]],
      decisions.assign_ruling_ids(["D3 Ship it", "Unnumbered", "**D3** again"])
  end

  def test_the_spec_decisions_win_over_the_main_files
    read = read("#{DIR}/spec.md" => "## Decisions\n- From spec\n", "#{DIR}/4--alpha.md" => "## Decisions\n- From main\n")

    assert_equal ["4", [["D1", "From spec"]]], read.values_at(:intent_id, :rulings)
  end

  def test_the_main_file_gives_the_rulings_when_the_spec_has_none
    assert_equal [["D1", "From main"]], read("#{DIR}/4--alpha.md" => "## Decisions\n- From main\n").fetch(:rulings)
  end

  def test_front_matter_names_the_sources_and_the_chain
    read = read("#{DIR}/4--alpha.md" => %(---\nsources: ["notes.md", "web"]\nchain: ["3"]\n---\n))

    assert_equal [%w[notes.md web], ["3"]], read.values_at(:source, :chain)
  end

  def test_a_dir_with_no_files_reads_empty
    assert_equal [[], [], []], read({}).values_at(:rulings, :source, :chain)
  end

  def write_decision
    counts = Hash.new(0)
    decision = { intent_id: "1", rulings: [["D1", "Ship it"]], source: ["notes.md"], chain: ["3"] }
    decisions.write_decisions(store_graphs.databases, [decision], counts)
    counts
  end

  def test_writing_decisions_counts_the_rulings_and_links
    assert_equal({ rulings: 1, links: 2 }, write_decision)
  end

  def test_writing_decisions_writes_the_ruling_rows
    write_decision

    assert_equal ["Ship it"], retrieval.rulings("1").map(&:text)
  end

  def test_writing_decisions_writes_the_source_and_chain_links
    write_decision

    assert_equal [%w[1 notes.md source], %w[1 3 chain]], retrieval.links("1").map { |link| [link.from_ref, link.to_ref, link.kind] }
  end
end
