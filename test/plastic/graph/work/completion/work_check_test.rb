# frozen_string_literal: true

require_relative "../../../../test_helper"

class WorkCompletionWorkCheckTest < Plastic::TestCase
  include LifecycleHelper

  def problem = Plastic::Graph::Work::Completion::Check.new(retrieval, "1").record_problems.join("\n")

  def test_every_criterion_covered_by_a_done_node_has_no_problem
    specified
    delivered_nodes

    refute_includes problem, "works"
  end

  def test_a_criterion_with_no_done_live_node_is_named_uncovered
    specified({ KEY => CRITERION, "extra" => "Also" })
    delivered_nodes({ KEY => CRITERION })

    assert_match(/extra/, problem)
  end

  def test_a_criterion_covered_only_by_a_removed_node_is_named_uncovered
    specified
    cli("node", "add", "1", "Build", "--criterion", KEY)
    cli("node", "remove", "1", "n1")

    assert_match(/#{KEY}/, problem)
  end

  def test_a_node_whose_key_the_spec_no_longer_has_is_named_with_its_key
    specified({ KEY => CRITERION, "gone" => "Soon gone" })
    delivered_nodes({ KEY => CRITERION, "gone" => "Soon gone" })
    write("#{retrieval.intent("1").dir}/spec.md", keyed_spec)
    sync_up

    assert_includes problem, "- n2 (gone)"
    refute_includes problem, "Fix the spec"
  end

  def test_a_done_node_with_findings_and_no_judge_counts_as_verified
    specified
    delivered_nodes

    refute_match(/findings/, problem)
  end

  def test_a_done_node_with_blank_findings_is_unverified
    specified
    delivered_nodes
    store_graphs.databases.fetch(:work).transaction { |batch| batch.add("UPDATE nodes SET findings = NULL") }

    assert_match(/findings/, problem)
  end

  def test_the_texts_do_not_name_a_judge_option
    specified
    delivered_nodes
    store_graphs.databases.fetch(:work).transaction { |batch| batch.add("UPDATE nodes SET findings = NULL") }

    refute_includes problem, "--judge"
  end
end
