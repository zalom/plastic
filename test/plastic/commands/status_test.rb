# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/status"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/node_claim"

class StatusTest < Plastic::TestCase
  def call(*args) = plastic("status", *args, table: Plastic::CLI::TABLE)

  def test_a_registered_project_without_a_store_names_its_path_in_the_project_new_line
    File.write(File.join(@plastic_home, "projects.yml"), "---\nprojects:\n  blog:\n    path: /tmp/blog\n")

    result = call("--project", "blog")

    assert_includes result.out, "run plastic project new blog /tmp/blog"
  end

  def test_a_project_without_a_store_offers_the_project_new_line_as_next
    File.write(File.join(@plastic_home, "projects.yml"), "---\nprojects:\n  blog:\n    path: /tmp/blog\n")

    result = call("--project", "blog")

    assert_equal ["next: plastic project new blog /tmp/blog"], result.out.lines(chomp: true).grep(/\Anext: /)
  end

  def test_a_second_store_is_not_missed
    open_keyed_intent
    Plastic::Graph.create(home: @plastic_home, store: "other").work.write_intent(title: "Beta")

    result = call

    assert_equal 0, result.code
    assert_includes result.out, "other"
    assert_includes result.out, "Beta"
  end

  def test_status_for_one_project_lists_only_its_store
    open_keyed_intent
    Plastic::Graph.create(home: @plastic_home, store: "other").work.write_intent(title: "Beta")

    result = call("--project", "other")

    assert_equal 0, result.code
    assert_match(/store:\s+other/, result.out)
    assert_includes result.out, "Beta"
    refute_match(/store:\s+global/, result.out)
  end

  def test_a_call_scoped_to_global_by_fallback_gets_no_project_in_its_next_line
    open_keyed_intent

    assert_includes call.out.lines(chomp: true), "next: plastic next"
  end

  def test_a_call_that_named_the_project_keeps_it_in_its_next_line
    open_keyed_intent

    assert_includes call("--project", "global").out.lines(chomp: true), "next: plastic next --project global"
  end

  def test_status_offers_plastic_next_as_the_next_command
    open_keyed_intent

    result = call

    assert_includes result.out, "next: plastic next"
  end

  def test_an_intent_without_nodes_says_so
    open_keyed_intent

    assert_includes call.out, "no nodes"
  end

  def test_counts_the_nodes_of_an_intent_by_state
    open_keyed_intent
    2.times { |i| plastic("node", "add", "1", "node #{i}", "--criterion", "done", table: Plastic::CLI::TABLE) }
    plastic("node", "claim", "1", "n1", table: Plastic::CLI::TABLE)

    assert_includes call.out, "claimed: 1, open: 1"
    assert_equal 0, call.code
    assert_equal "", call.err
  end
end
