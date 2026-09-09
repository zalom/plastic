# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require_relative "../scripts/lib/savepoint"

# Savepoint.derive_stage learns the node shape (intent 336, n7, D13): 327 D41
# removes plan.md and checklist.md from a node-graph intent's common path, so
# a real graph.md plus real node files must read Exec whether or not spec.md
# is real. Uses only savepoint.rb's own primitives (stage_file_present?,
# has_real_files_in?), because test/savepoint_split_test.rb pins this file to
# loading no other project file and no YAML.
class DeriveStageNodeShapeTest < Minitest::Test
  SENTINEL = Savepoint::PLACEHOLDER_SENTINEL

  def setup
    @root = Dir.mktmpdir("derive-stage-node-shape")
    @intent_dir = File.join(@root, "336--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "336--demo.md"), "## Intent\nDemo\n\n## Context\nWhy\n")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write_graph(body = "# Graph\n\n## Graph\n- n1 needs nothing\n")
    File.write(File.join(@intent_dir, "graph.md"), body)
  end

  def write_node(id)
    FileUtils.mkdir_p(File.join(@intent_dir, "nodes"))
    File.write(File.join(@intent_dir, "nodes", "#{id}.md"), "# #{id}\nreal\n")
  end

  def test_node_shaped_intent_with_nodes_derives_exec
    write_graph
    write_node("n1")
    assert_equal "exec", Savepoint.derive_stage(@intent_dir)
  end

  def test_node_shaped_intent_reaches_exec_without_a_spec
    refute File.exist?(File.join(@intent_dir, "spec.md"))
    write_graph
    write_node("n1")
    assert_equal "exec", Savepoint.derive_stage(@intent_dir)
  end

  def test_graph_without_nodes_derives_how
    write_graph
    assert_equal "how", Savepoint.derive_stage(@intent_dir)
  end

  def test_outcome_still_wins
    write_graph
    write_node("n1")
    File.write(File.join(@intent_dir, "outcome.md"), "# Outcome\nreal\n")
    assert_equal "done", Savepoint.derive_stage(@intent_dir)
  end

  def test_legacy_intent_stage_is_byte_for_byte_unchanged
    File.write(File.join(@intent_dir, "spec.md"), "# Spec\nreal\n")
    File.write(File.join(@intent_dir, "plan.md"), "# Plan\nreal\n")
    File.write(File.join(@intent_dir, "checklist.md"), "# Checklist\nreal\n")
    FileUtils.mkdir_p(File.join(@intent_dir, "actions"))
    File.write(File.join(@intent_dir, "actions", "ACTION_1.md"), "# Action\nreal\n")
    assert_equal "exec", Savepoint.derive_stage(@intent_dir)
  end

  def test_placeholder_graph_does_not_advance_the_stage
    write_graph("#{SENTINEL}\n")
    write_node("n1")
    assert_equal "why", Savepoint.derive_stage(@intent_dir)
  end

  def test_savepoint_still_loads_exactly_itself
    root = File.expand_path("../", __dir__)
    savepoint_path = File.join(root, "scripts", "lib", "savepoint.rb")
    script = <<~RUBY
      require "json"
      before = $LOADED_FEATURES.dup
      require #{savepoint_path.inspect}
      loaded = ($LOADED_FEATURES.dup - before).select { |f| f.end_with?(".rb") && f.start_with?(#{root.inspect}) }
      puts JSON.generate(loaded.map { |f| File.basename(f) })
    RUBY
    script_path = File.join(@root, "probe.rb")
    File.write(script_path, script)
    out, err, status = Open3.capture3("ruby", script_path)
    assert status.success?, err
    assert_equal %w[savepoint.rb], JSON.parse(out)
  end

  def test_has_files_lists_graph_md_when_real
    write_graph
    assert_includes Savepoint.has_files(@intent_dir), "graph.md"
  end

  def test_missing_for_stage_names_graph_and_nodes_for_a_node_intent
    write_graph
    assert_equal ["graph.md", "nodes/"], Savepoint.missing_for_stage("how", @intent_dir)
  end
end
