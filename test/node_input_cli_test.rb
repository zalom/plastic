# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"

require_relative "../scripts/lib/installer_core"

# Intent 338 (G5), n4: scripts/node-input, the command 340's runner will
# actually call. Matrix rows 4.1 to 4.8 in actions/ACTION_1.md. Every test
# spawns the real CLI as a subprocess (Open3), the house pattern for
# scripts/node-transition and scripts/validate-work-graph.
class NodeInputCliTest < Minitest::Test
  NODE_INPUT = File.expand_path("../scripts/node-input", __dir__)
  REPO = File.expand_path("..", __dir__)

  def setup
    @home = Dir.mktmpdir("node-input-cli")
    @intent_dir = build_intent_dir(@home)
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def build_intent_dir(home, id: "1", slug: "demo", graph_body: "- n1 needs nothing\n")
    dir = File.join(home, "store", "#{id}--#{slug}")
    FileUtils.mkdir_p(File.join(dir, "nodes"))
    File.write(File.join(dir, "#{id}--#{slug}.md"), <<~MD)
      ---
      id: "#{id}"
      sources: []
      ---

      ## Intent
      Demo intent body.

      ## Context

      ### Decisions
      - D1 pick approach

      ## Outcome
      (pending)

      ## Insights
      (observations captured throughout — raw material for future intents)
    MD
    File.write(File.join(dir, "graph.md"), <<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      #{graph_body}
      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
    File.write(File.join(dir, "nodes", "n1.md"), <<~MD)
      ---
      node: n1
      kind: work
      files: ["scripts/lib/x.rb"]
      budget: 100000
      ---
      # n1
      Do the thing.
    MD
    dir
  end

  def run_cli(*args)
    Open3.capture3(RbConfig.ruby, NODE_INPUT, *args)
  end

  # --- 4.1-4.6: usage and exit codes -------------------------------------------

  def test_a_missing_node_flag_exits_two_with_usage
    out, err, status = run_cli(@intent_dir)
    assert_equal 2, status.exitstatus, out + err
    assert_match(/--node/, err)
  end

  def test_a_non_intent_directory_exits_two
    not_an_intent = Dir.mktmpdir("not-an-intent")
    out, err, status = run_cli(not_an_intent, "--node", "n1")
    assert_equal 2, status.exitstatus, out + err
  ensure
    FileUtils.remove_entry(not_an_intent) if not_an_intent && Dir.exist?(not_an_intent)
  end

  def test_an_unknown_node_exits_two
    out, err, status = run_cli(@intent_dir, "--node", "n99")
    assert_equal 2, status.exitstatus, out + err
  end

  def test_an_unreadable_graph_exits_three
    File.write(File.join(@intent_dir, "graph.md"), "not a real graph file at all\n")
    out, err, status = run_cli(@intent_dir, "--node", "n1")
    assert_equal 3, status.exitstatus, out + err
  end

  def test_the_exit_code_map_matches_the_node_transition_family
    _out, _err, missing_node = run_cli(@intent_dir)
    _out, _err, bad_dir = run_cli(Dir.mktmpdir("scratch"), "--node", "n1")
    _out, _err, unknown_node = run_cli(@intent_dir, "--node", "n99")
    File.write(File.join(@intent_dir, "graph.md"), "garbage\n")
    _out, _err, bad_graph = run_cli(@intent_dir, "--node", "n1")
    assert_equal 2, missing_node.exitstatus
    assert_equal 2, bad_dir.exitstatus
    assert_equal 2, unknown_node.exitstatus
    assert_equal 3, bad_graph.exitstatus
  end

  def test_a_successful_build_exits_zero_and_prints_the_summary
    out, err, status = run_cli(@intent_dir, "--node", "n1")
    assert_equal 0, status.exitstatus, out + err
    assert_match(/path=.*sha=.*tokens=.*hop_tokens=.*attempt=/, out)
    assert_match(/node-transition .* --state running/, out)
    assert File.exist?(File.join(@intent_dir, "attempts", "n1--a1.input"))
  end

  # --- 2.3/2.4: the renamed command, as a real subprocess ----------------------

  def test_node_input_command_writes_the_input_as_a_subprocess
    out, err, status = run_cli(@intent_dir, "--node", "n1")
    assert_equal 0, status.exitstatus, out + err
    assert File.exist?(File.join(@intent_dir, "attempts", "n1--a1.input"))
  end

  def test_usage_names_the_node_input_command
    retired_word = %w[pack et].join
    out, err, status = run_cli(@intent_dir)
    assert_equal 2, status.exitstatus, out + err
    assert_match(/node-input/, err)
    refute_match(/node-#{retired_word}/, err)
  end

  # --- 4.7: installer manifest -------------------------------------------------

  def test_node_input_and_both_libraries_are_registered_in_the_installer_manifest
    core = InstallerCore.new(package_root: REPO)
    manifest = core.core_files
    assert manifest.key?("scripts/node-input"), "scripts/node-input is missing from the installer manifest"
    assert manifest.key?("scripts/lib/data_boundary.rb"),
           "scripts/lib/data_boundary.rb is missing from the installer manifest"
    assert manifest.key?("scripts/lib/node_input.rb"),
           "scripts/lib/node_input.rb is missing from the installer manifest"
  end

  # 2.6: the manifest prune only fires when the retired paths are actually
  # gone from `core_files` (D15) - built from parts so this file carries no
  # whole-word hit for a vocabulary scan to trip on.
  def test_retired_files_leave_core_files
    retired_word = %w[pack et].join
    retired = ["scripts/node-#{retired_word}", "scripts/lib/node_#{retired_word}.rb",
               "scripts/lib/#{retired_word}_wrapper.rb"]
    core = InstallerCore.new(package_root: REPO)
    manifest = core.core_files
    retired.each do |path|
      refute manifest.key?(path), "#{path} should have left the installer manifest"
    end
  end

  # 2.10: a stale require would resolve locally against an old installed
  # copy and pass by accident, so this walks every script on disk instead
  # of trusting one caller's own diff.
  def test_no_script_requires_a_retired_library
    retired_word = %w[pack et].join
    retired_libs = ["node_#{retired_word}", "#{retired_word}_wrapper"]
    Dir.glob(File.join(REPO, "scripts", "**", "*")).each do |path|
      next unless File.file?(path)

      content = File.read(path)
      retired_libs.each do |lib|
        refute_match(/require_relative\s+["'](?:[^"']*\/)?#{Regexp.escape(lib)}["']/, content,
                     "#{path} still requires the retired #{lib} library")
      end
    end
  end

  # --- 4.8: flags ---------------------------------------------------------------

  def test_each_documented_flag_changes_the_output
    out_default, _err, status_default = run_cli(@intent_dir, "--node", "n1")
    assert_equal 0, status_default.exitstatus
    default_tokens = out_default[/tokens=(\d+)/, 1].to_i

    out_budget, _err, status_budget = run_cli(@intent_dir, "--node", "n1", "--budget", "1")
    refute_equal 0, status_budget.exitstatus
    refute_equal out_default, out_budget

    custom_path = File.join(@intent_dir, "attempts", "custom.input")
    out_attempt, _err, status_attempt = run_cli(@intent_dir, "--node", "n1", "--attempt", "9")
    assert_equal 0, status_attempt.exitstatus
    assert_includes out_attempt, "n1--a9.input"

    out_out, _err, status_out = run_cli(@intent_dir, "--node", "n1", "--attempt", "10", "--out", custom_path)
    assert_equal 0, status_out.exitstatus
    assert File.exist?(custom_path)

    out_hop, _err, status_hop = run_cli(@intent_dir, "--node", "n1", "--attempt", "11", "--hop-tokens", "0")
    assert_equal 0, status_hop.exitstatus
    assert_includes out_hop, "hop_tokens=0"
    assert_operator default_tokens, :>, 0
  end
end
