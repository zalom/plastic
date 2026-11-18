# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeLegacyDecisionsTest < Plastic::TestCase
  DIR = "store/4--alpha"

  Decisions = Plastic::Graph::Knowledge::Legacy::Decisions

  def read(originals) = Decisions.read([DIR], originals).first

  def test_rulings_keep_their_numbers_and_take_the_next_free_one_otherwise
    assert_equal [["D3", "D3 Ship it"], ["D4", "Unnumbered"], ["D5", "**D3** again"]],
      Decisions.assign_ruling_ids(["D3 Ship it", "Unnumbered", "**D3** again"])
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
end
