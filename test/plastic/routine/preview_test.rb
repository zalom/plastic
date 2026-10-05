# frozen_string_literal: true

require_relative "../../test_helper"
%w[intent_archive intent_unlink node_remove edge_remove roadmap_drop roadmap_edge_remove graph_show roadmap_show].each do |name|
  require_relative "../../../scripts/lib/plastic/commands/#{name}"
end

class RoutinePreviewTest < Plastic::TestCase
  COMMANDS = [Plastic::Commands::IntentArchive, Plastic::Commands::IntentUnlink, Plastic::Commands::NodeRemove,
    Plastic::Commands::EdgeRemove, Plastic::Commands::RoadmapDrop, Plastic::Commands::RoadmapEdgeRemove,
    Plastic::Commands::GraphShow, Plastic::Commands::RoadmapShow].freeze

  # A chain that holds an agent workflow, with the preview declared.
  class PreviewedDraft < Fixtures::Routine
    argument :name, label: "NAME", text: "the draft's name"
    option :dir, switch: "--dir DIR", text: "where the draft goes"
    previews

    workflow :code_stamp, next: :code_find_draft
    workflow :code_find_draft, next: :agent_write_draft
    workflow :agent_write_draft, next: :noop
  end

  def seed_graph(home)
    seed_intents(home, "Alpha")
    seed_nodes(home, "a")
  end

  def test_each_removing_command_declares_the_dry_run_switch
    declared = COMMANDS.map do |command|
      command.describe.to_h[:options].find { |option| option[:name] == :dry_run }&.slice(:switch, :default, :text)
    end

    assert_equal [{ switch: "--dry-run", default: false, text: "preview the call in a disposable copy" }] * COMMANDS.size, declared
  end

  def test_a_preview_leaves_every_byte_of_the_home_unchanged
    twin = twin_run("graph", "show", "1") { |home| seed_graph(home) }

    assert_equal 0, twin.previewed.code, twin.previewed.err
    assert_equal [], twin.changed_paths
  end

  def test_a_preview_keeps_no_routine_run
    twin = twin_run("graph", "show", "1") { |home| seed_graph(home) }

    assert_nil home_graphs(twin.first).retrieval.routine_run("graph show", "1")
    assert home_graphs(twin.second).retrieval.routine_run("graph show", "1")
  end

  def test_a_preview_names_original_paths_never_the_copy
    twin = twin_run("graph", "show", "1") { |home| seed_graph(home) }

    refute_includes twin.previewed.out, "plastic-preview"
    assert_includes twin.previewed.out, "preview: would change #{twin.first}/stores/global/store/1--alpha/graph.json"
  end

  def test_a_preview_prefixes_every_printed_line_and_ends_on_the_closing_line
    twin = twin_run("graph", "show", "1") { |home| seed_graph(home) }
    printed = twin.previewed.out.lines(chomp: true).take_while { |line| !line.empty? }
    rows = printed.reject { |line| line.start_with?("preview: ") || line.start_with?("would write:") }

    assert_equal ["preview complete; the original store was not changed"], rows
    assert_equal "preview: node: n1 open a", printed.first
  end

  def test_a_preview_offers_the_same_command_without_dry_run
    twin = twin_run("graph", "show", "1") { |home| seed_graph(home) }

    assert_includes twin.previewed.out, "next: plastic graph show 1 --project global\n"
    assert_includes twin.previewed.out, "because: the preview wrote only to a disposable copy\n"
  end

  def test_the_next_command_quotes_an_argument_with_a_space_and_keeps_the_project
    twin = twin_run("node", "remove", "1", "n1", "--reason", "not needed", "--project", "global") { |home| seed_graph(home) }

    assert_includes twin.previewed.out, "next: plastic node remove 1 n1 --reason not\\ needed --project global\n"
  end

  def test_a_json_preview_returns_the_preview_lines_and_the_next_command
    twin = twin_run("graph", "show", "1", "--json") { |home| seed_graph(home) }
    document = JSON.parse(twin.previewed.out)

    assert_equal "preview: node: n1 open a", document.dig("result", "output").first
    assert_equal "preview complete; the original store was not changed", document.dig("result", "output").last
    assert_equal "plastic graph show 1 --json --project global", document["next"]
  end

  def test_a_preview_after_a_refused_apply_matches_the_resumed_apply
    twin = twin_run("intent", "archive", "1") do |home|
      seed_intents(home, "Alpha")
      assert_equal 3, call_in(home, "intent", "archive", "1").code
      mark_done(home, "1")
    end

    assert_preview_matches_apply(twin)
    assert_equal 0, twin.previewed.code
  end

  def test_a_refusal_in_the_copy_prints_the_apply_message_and_the_closing_line
    twin = twin_run("intent", "archive", "1") { |home| seed_intents(home, "Alpha") }

    assert_equal 3, twin.previewed.code
    assert_equal twin.applied.err, twin.previewed.err
    assert_includes twin.previewed.out, "preview complete; the original store was not changed\n"
    assert_equal [], twin.changed_paths
  end

  def test_verify_rejects_previews_on_a_chain_with_an_agent_workflow
    error = assert_raises(Plastic::Invalid) { PreviewedDraft.verify }

    assert_includes error.message, "agent_write_draft"
    assert_includes error.message, "preview"
  end
end
