# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/status"
require_relative "../../../lib/plastic/commands/node/add"
require_relative "../../../lib/plastic/commands/node/claim"

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
  end

  def test_a_second_store_lists_its_intents
    open_keyed_intent
    Plastic::Graph.create(home: @plastic_home, store: "other").work.write_intent(title: "Beta")

    assert_includes call.out, "Beta"
  end

  def test_status_for_one_project_lists_only_its_store
    open_keyed_intent
    Plastic::Graph.create(home: @plastic_home, store: "other").work.write_intent(title: "Beta")

    result = call("--project", "other")

    assert_equal 0, result.code
    assert_match(/store:\s+other/, result.out)
    refute_match(/store:\s+global/, result.out)
  end

  def test_status_for_one_project_lists_its_intents
    open_keyed_intent
    Plastic::Graph.create(home: @plastic_home, store: "other").work.write_intent(title: "Beta")

    assert_includes call("--project", "other").out, "Beta"
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

  def test_the_intents_are_listed_in_the_groups_active_future_and_finished_in_that_order
    { "Moving" => "in_progress", "Later" => "future", "Shipped" => "done", "Waiting" => "open" }.each { |title, status| store_graphs.work.write_intent(title:, status:) }

    lines = call.out.lines(chomp: true)
    groups = %w[active: future: finished:].map { |word| lines.index { |line| line.start_with?(word) } }

    assert_equal groups.sort, groups
    refute_includes groups, nil
  end

  def test_each_intent_shows_its_state_beside_its_title_in_its_group
    { "Moving" => "in_progress", "Later" => "future", "Shipped" => "done", "Quit" => "abandoned" }.each { |title, status| store_graphs.work.write_intent(title:, status:) }

    out = call.out

    assert_equal ["1 Moving (in_progress)", "2 Later (future)", "3 Shipped (done)", "4 Quit (abandoned)"], out.scan(/\d \w+ \(\w+\)/)
  end

  def test_a_group_without_an_intent_prints_no_line
    store_graphs.work.write_intent(title: "Waiting")

    out = call.out

    assert_match(/^active:/, out)
    refute_match(/^future:|^finished:/, out)
  end

  def test_a_group_past_the_listing_cap_ends_with_how_many_more_there_are
    (Plastic::Graph::Knowledge::Intent::Listing::MAX + 2).times { |index| store_graphs.work.write_intent(title: "Item #{index}") }

    out = call.out

    assert_includes out, "and 2 more"
    assert_equal Plastic::Graph::Knowledge::Intent::Listing::MAX, out.scan("(open)").size
  end
end
