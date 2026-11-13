# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeRoadmapParseTest < Plastic::TestCase
  def parse(text) = Plastic::Graph::Knowledge::Roadmap::Parse.call(text, path: "roadmaps/r1.md")

  def test_a_status_followed_by_more_words_still_reads
    result = parse("# R1\n\n## Batches\n\n### Batch 1 — First\n- [ ] 7 Build it — queued, deferred to later\n")

    item = sole(result.items)

    assert_equal %w[7 queued Build\ it], [item.item, item.status, item.title]
    assert_empty result.problems
  end

  def graph(text) = parse("# R1\n\n## Graph\n#{text}\n")

  def test_a_needs_line_splits_its_targets_on_commas
    result = graph("- 1 needs 2, 3")

    assert_equal({ "1" => %w[2 3] }, result.edges)
    assert_empty result.problems
  end

  def test_a_needs_line_with_spaces_gives_the_same_edges
    assert_equal({ "1" => %w[2 3] }, graph("- 1 needs 2 3").edges)
  end

  def test_a_needs_line_with_commas_and_no_spaces_gives_the_same_edges
    assert_equal({ "1" => %w[2 3] }, graph("- 1 needs 2,3").edges)
  end

  def batches(text) = parse("# R1\n\n## Batches\n\n### Batch 1 — First\n#{text}\n")

  def test_an_item_continues_on_the_line_below_it
    item = sole(batches("- [ ] 7 Build it\n  with more words — queued\n").items)

    assert_equal "Build it with more words", item.title
  end

  def test_a_line_before_any_item_is_ignored
    result = batches("Some words first\n- [ ] 7 Build it — queued\n")

    assert_equal 1, result.items.size
    assert_empty result.problems
  end

  def test_a_blank_line_ends_the_item_above_it
    result = batches("- [ ] 7 Build it — queued\n\nloose words\n")

    assert_equal 1, result.items.size
  end

  def test_an_item_that_cannot_be_read_is_a_problem
    assert_equal 1, batches("- [ ]\n").problems.size
  end

  def test_an_item_with_no_status_is_a_problem
    assert_equal 1, batches("- [ ] 7 Build it\n").problems.size
  end

  def test_an_item_with_an_id_that_is_not_plain_is_a_problem
    assert_equal 1, batches("- [ ] a/b Build it — queued\n").problems.size
  end

  def test_a_nothing_root_gives_no_targets
    assert_equal({ "1" => [] }, graph("- 1 needs nothing").edges)
  end

  def test_a_graph_line_with_no_target_is_a_problem
    result = graph("- 1 needs")

    assert_empty result.edges
    assert_equal 1, result.problems.size
  end

  def test_a_root_mixed_with_a_real_target_is_a_problem
    assert_equal 1, graph("- 1 needs nothing 2").problems.size
  end

  def test_a_target_that_is_not_a_plain_id_is_a_problem
    assert_equal 1, graph("- 1 needs a/b").problems.size
  end

  def test_a_graph_line_that_is_not_a_needs_line_is_ignored
    result = graph("- some other note")

    assert_empty result.edges
    assert_empty result.problems
  end

  def test_a_log_line_without_a_date_is_a_problem
    assert_equal 1, parse("# R1\n\n## Log\n- no date here\n").problems.size
  end

  def test_a_blank_line_ends_the_log_line_above_it
    result = parse("# R1\n\n## Log\n- 2026-09-01 Opened\n\nloose words\n- 2026-09-02 Closed\n")

    assert_equal 2, result.log.size
  end

  def test_a_goal_joins_its_lines_and_skips_the_blank_ones
    assert_equal "One two", parse("# R1\n\n## Goal\n\nOne\n\n two \n").goal
  end

  def test_a_goal_with_no_words_is_nil
    assert_nil parse("# R1\n\n## Goal\n\n").goal
  end

  def test_a_section_with_an_unknown_heading_is_ignored
    result = parse("# R1\n\n## Notes\n- 2026-09-01 Not a log line\n")

    assert_empty result.log
    assert_empty result.problems
  end

  def test_a_file_without_a_title_has_none
    assert_nil parse("loose words\n").title
  end

  def test_an_indented_bullet_continues_the_log_line_above_it
    result = parse("# R1\n\n## Log\n- 2026-09-01 Opened the roadmap\n  - with a sub-point\n- 2026-09-02 Closed it\n")

    assert_equal 2, result.log.size
    assert_includes result.log.first.text, "with a sub-point"
    assert_empty result.problems
  end
end
