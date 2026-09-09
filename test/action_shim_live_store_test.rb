# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/lib/action_graph_shim"
require_relative "../scripts/lib/work_graph_validator"
require_relative "../scripts/lib/node_file"

# ActionShimLiveStoreTest (intent 342, v1): the shim and the validator's
# actions-only branch proved against copies of real intent directories
# rather than invented fixtures (spec.md S3). Read-only: every fixture under
# test/fixtures/legacy_intents/ and test/fixtures/dogfood_intent/ is a
# frozen copy, never the live store itself.
class ActionShimLiveStoreTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  FIXTURES = File.join(REPO, "test", "fixtures", "legacy_intents")

  FIXTURE_IDS = %w[193 195 197 211 235 331 82].freeze

  def fixture_dir(id)
    File.join(FIXTURES, id)
  end

  def real_action_file_count(id)
    Dir.glob(File.join(fixture_dir(id), "actions", "*.md"))
       .select { |f| File.file?(f) && File.size(f) > 0 }
       .length
  end

  def test_every_fixture_resolves_to_actions
    FIXTURE_IDS.each do |id|
      assert_equal :actions, ActionGraphShim.shape(fixture_dir(id)), "fixture #{id} did not resolve to :actions"
    end
  end

  def test_197_orders_action_10_after_action_2
    nodes = ActionGraphShim.nodes(fixture_dir("197"))
    by_path = {}
    nodes.each { |n| by_path[File.basename(n[:path])] = n[:node] }
    assert_equal "n2", by_path["ACTION_2.md"]
    assert_equal "n10", by_path["ACTION_10.md"]
  end

  def test_235_node_2_declares_no_files
    nodes = ActionGraphShim.nodes(fixture_dir("235"))
    node2 = nodes.find { |n| File.basename(n[:path]) == "ACTION_2.md" }
    refute_nil node2, "235 fixture must carry ACTION_2.md"
    assert_equal [], node2[:files]
  end

  def test_82_hyphen_form_becomes_a_chain
    nodes = ActionGraphShim.nodes(fixture_dir("82"))
    refute_empty nodes
    assert_equal real_action_file_count("82"), nodes.length
    assert_equal (1..nodes.length).map { |i| "n#{i}" }, nodes.map { |n| n[:node] }
    edges = ActionGraphShim.view(fixture_dir("82"))[:graph][:edges]
    roots = edges.select { |_id, targets| targets.empty? }
    assert_equal 1, roots.length
  end

  def test_every_fixture_validates_ok
    FIXTURE_IDS.each do |id|
      dir = fixture_dir(id)
      nodes = ActionGraphShim.nodes(dir)
      assert_equal real_action_file_count(id), nodes.length, "node count mismatch for #{id}"
      assert_equal (1..nodes.length).map { |i| "n#{i}" }, nodes.map { |n| n[:node] }, "ids not n1..nN in order for #{id}"

      edges = ActionGraphShim.view(dir)[:graph][:edges]
      require_relative "../scripts/lib/graph_edges"
      refute GraphEdges.cycle(edges), "fixture #{id} must be acyclic"
      roots = edges.select { |_id, targets| targets.empty? }
      assert_equal 1, roots.length, "fixture #{id} must have exactly one root"

      result = WorkGraphValidator.validate(dir)
      assert result[:ok], "fixture #{id} failed validation: #{result[:errors].inspect}"
      assert_equal [], result[:missing], "fixture #{id} reported missing: #{result[:missing].inspect}"
      assert_equal [], result[:errors], "fixture #{id} reported errors: #{result[:errors].inspect}"
    end
  end

  def test_dogfood_files_stop_at_the_out_of_bounds_clause
    dogfood_dir = File.join(REPO, "test", "fixtures", "dogfood_intent")
    node = ActionGraphShim.nodes(dogfood_dir).first
    out_of_bounds = %w[
      scripts/hook-capture .github/ project.yml scripts/node-transition
      scripts/lib/report_screen.rb scripts/end-intent
    ]
    out_of_bounds.each do |path|
      refute_includes node[:files], path, "out-of-bounds path #{path} leaked into files"
    end
    # Harvesting stops at the first body line carrying a negation (D17),
    # scanning only what precedes it. That line, in this action file's own
    # "Files to touch" list, is the fifth bullet ("never edit an existing
    # assertion" on test/work_graph_validator_test.rb): a coincidental
    # negation about editing assertions inside a file, not about the file
    # being out of bounds, but D17's rule is deliberately line-simple, not
    # semantic, so it stops there too. Only the four bullets before it are
    # scanned; none of the out-of-bounds paths past the negation, nor the
    # bullets after it, come back.
    in_bounds_first = %w[
      scripts/lib/action_graph_shim.rb scripts/lib/work_graph_validator.rb
      scripts/lib/installer_core.rb test/action_graph_shim_test.rb
    ]
    assert_equal in_bounds_first, node[:files]
  end

  def test_dogfood_record_key_set_matches_authored_node
    dogfood_dir = File.join(REPO, "test", "fixtures", "dogfood_intent")
    action_path = File.join(dogfood_dir, "actions", "ACTION_1.md")
    node_path = File.join(dogfood_dir, "nodes", "n1.md")

    synthetic = ActionGraphShim.nodes(dogfood_dir).first
    authored = NodeFile.parse(node_path)

    expected_keys = (authored.keys + %i[needs path proven_by]).sort
    assert_equal expected_keys, synthetic.keys.sort
    assert_equal "n1", synthetic[:node]
    assert_equal "work", synthetic[:kind]
    assert File.exist?(action_path)
  end
end
