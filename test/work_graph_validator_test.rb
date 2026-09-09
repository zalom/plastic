# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../scripts/lib/work_graph_validator"
require_relative "../scripts/lib/report_screen"

# WorkGraphValidator (intent 334, n4): the in-batch reader over graph.md and
# nodes/ (327's rule for budget, files, and the decision/research kinds,
# fold A17). Named apart from IntentValidator#validate_graph, which already
# exists for the knowledge graph and stays unrelated under D40 (fold B9).
class WorkGraphValidatorTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/validate-work-graph", __dir__)

  def setup
    @dir = Dir.mktmpdir("work-graph-validator")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write_graph(graph_body, decisions: "- D1 pick approach", goal: "Ship it.")
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Demo

      ## Goal
      #{goal}

      ## Decisions
      #{decisions}

      ## Graph
      #{graph_body}
      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
  end

  MATRIX = <<~MD
    | Operation | Failure mode | Test |
    | --- | --- | --- |
    | op | mode | a test |
  MD

  def write_node(filename, node:, kind:, files: ["scripts/lib/x.rb"], budget: 100_000, body:)
    path = File.join(@dir, "nodes", filename)
    File.write(path, <<~MD)
      ---
      node: #{node}
      kind: #{kind}
      files: #{files.inspect}
      budget: #{budget}
      ---
      #{body}
    MD
    path
  end

  def work_body(id, with_matrix: false)
    matrix = with_matrix ? "\n## #{id} failure-mode matrix\n#{MATRIX}\n" : "\n"
    "# #{id} - a work node\n#{matrix}\n## Steps\n1. do it\n\n## Proven by\n(filled at close)\n"
  end

  # --- check needs targets -----------------------------------------------------

  def test_dangling_needs_target_fails
    write_graph("- n1 needs n2\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1"))
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("n2") })
  end

  # --- check verify/decision/research nodes -------------------------------------

  def test_verify_node_without_criteria_fails
    write_graph("- v1 needs nothing\n- n1 needs v1\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1"))
    write_node("v1.md", node: "v1", kind: "verify", body: "# v1 - review\n\nProse only, no criteria.\n")
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("Criteria") })
  end

  def test_decision_node_without_question_fails
    write_graph("- d1 needs nothing\n- n1 needs d1\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1"))
    write_node("d1.md", node: "d1", kind: "decision", body: "# d1 - a choice\n\n## Question\n")
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("Question") })
  end

  def test_research_node_without_deposit_fails
    write_graph("- r1 needs nothing\n- n1 needs r1\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1"))
    write_node("r1.md", node: "r1", kind: "research", body: "# r1 - a question\n\nProse only.\n")
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("Deposit") })
  end

  def test_work_node_requires_steps_and_proven_by
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work", body: "# n1 - a work node\n\nProse only, no Steps or Proven by.\n")
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("Steps") })
    assert(result[:errors].any? { |e| e.include?("Proven by") })
  end

  # --- attach a verify node ------------------------------------------------------

  def test_two_work_nodes_without_verify_fails
    write_graph("- n1 needs nothing\n- n2 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1", with_matrix: true))
    write_node("n2.md", node: "n2", kind: "work", body: work_body("n2", with_matrix: true))
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("verify") })
  end

  def test_unattached_verify_node_fails
    write_graph("- n1 needs nothing\n- n2 needs nothing\n- v1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1", with_matrix: true))
    write_node("n2.md", node: "n2", kind: "work", body: work_body("n2", with_matrix: true))
    write_node("v1.md", node: "v1", kind: "verify", body: "# v1 - review\n\n## Criteria\ndone\n")
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("v1") && (e.include?("attach") || e.include?("reaches")) })
  end

  def test_verify_none_with_reason_passes
    write_graph("- n1 needs nothing\n- n2 needs nothing\n- verify: none reason=trivial cleanup\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1", with_matrix: true))
    write_node("n2.md", node: "n2", kind: "work", body: work_body("n2", with_matrix: true))
    result = WorkGraphValidator.validate(@dir)
    assert result[:ok], result[:errors].inspect
  end

  # --- trivial bar and matrix bar ------------------------------------------------

  def test_single_work_node_needs_no_matrix_or_verify
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1", with_matrix: false))
    result = WorkGraphValidator.validate(@dir)
    assert result[:ok], result[:errors].inspect
  end

  def test_matrix_required_above_the_trivial_bar
    write_graph("- n1 needs nothing\n- n2 needs nothing\n- v1 needs n1 n2\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1", with_matrix: true))
    write_node("n2.md", node: "n2", kind: "work", body: work_body("n2", with_matrix: false))
    write_node("v1.md", node: "v1", kind: "verify", body: "# v1 - review\n\n## Criteria\ndone\n")
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("n2") && e.include?("matrix") })
  end

  def test_matrix_heading_must_carry_the_node_id
    write_graph("- n1 needs nothing\n- n2 needs nothing\n- v1 needs n1 n2\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1", with_matrix: true))
    unlabeled = "# n2 - a work node\n\n## Failure-mode matrix\n#{MATRIX}\n## Steps\n1. do it\n\n## Proven by\n(filled at close)\n"
    write_node("n2.md", node: "n2", kind: "work", body: unlabeled)
    write_node("v1.md", node: "v1", kind: "verify", body: "# v1 - review\n\n## Criteria\ndone\n")
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("n2") && e.include?("matrix") })
  end

  def test_matrix_needs_columns_and_a_row
    write_graph("- n1 needs nothing\n- n2 needs nothing\n- v1 needs n1 n2\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1", with_matrix: true))
    empty_matrix = "# n2 - a work node\n\n## n2 failure-mode matrix\n| Operation | Failure mode | Test |\n| --- | --- | --- |\n\n## Steps\n1. do it\n\n## Proven by\n(filled at close)\n"
    write_node("n2.md", node: "n2", kind: "work", body: empty_matrix)
    write_node("v1.md", node: "v1", kind: "verify", body: "# v1 - review\n\n## Criteria\ndone\n")
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("n2") && e.include?("matrix") })
  end

  # --- reconcile files and graph --------------------------------------------------

  def test_undeclared_node_file_fails
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1"))
    write_node("n5--orphan.md", node: "n5", kind: "work", body: work_body("n5"))
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("n5") })
  end

  def test_declared_node_without_a_file_fails
    write_graph("- n9 needs nothing\n")
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("n9") })
  end

  def test_two_files_claiming_one_id_fails
    write_graph("- n1 needs nothing\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1"))
    write_node("n1--dup.md", node: "n1", kind: "work", body: work_body("n1"))
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("n1") && e.include?("more than one") })
  end

  # --- cycle at read ---------------------------------------------------------------

  def test_cycle_fails_validation
    write_graph("- n1 needs n2\n- n2 needs n1\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1"))
    write_node("n2.md", node: "n2", kind: "work", body: work_body("n2"))
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("cycl") })
  end

  # --- accumulate errors -------------------------------------------------------------

  def test_all_errors_are_reported_together
    write_graph("- n1 needs n2\n")
    write_node("n9.md", node: "n9", kind: "work", body: work_body("n9"))
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert_operator result[:errors].length, :>=, 2
  end

  # --- drift pin (post-execution review, non-blocking 9) ----------------------------
  #
  # WorkGraphValidator.heading_tokens re-implements ReportScreen.heading_tokens
  # (D7r's whole point is that the validator predicts the resolver's answer,
  # so the two must never drift apart).

  def test_heading_tokens_matches_report_screens_split_on_every_heading_shape
    headings = [
      "## n1 failure-mode matrix",
      "### The v2 rewrite (S3)",
      "## Criteria",
      "###n3-no-space--slug",
      "# Graph: Démo",
      "## 1. What this intent is",
    ]
    headings.each do |heading|
      assert_equal ReportScreen.heading_tokens(heading), WorkGraphValidator.heading_tokens(heading),
                   "heading_tokens must split #{heading.inspect} identically in both places"
    end
  end

  # --- CLI ---------------------------------------------------------------------------

  def run_cli(*args)
    out, err, status = Open3.capture3(RbConfig.ruby, SCRIPT, *args)
    [out, err, status.exitstatus]
  end

  def test_cli_exits_1_on_an_invalid_graph
    write_graph("- n1 needs n2\n")
    _out, _err, status = run_cli(@dir)
    assert_equal 1, status
  end

  def test_cli_errors_go_to_stderr
    write_graph("- n1 needs n2\n")
    out, err, _status = run_cli(@dir)
    assert_empty out
    refute_empty err
  end

  def test_cli_exits_2_only_without_an_argument
    _out, _err, status = run_cli
    assert_equal 2, status

    write_graph("- n1 needs n2\n")
    _out2, _err2, status2 = run_cli(File.join(@dir, "no-such-dir"))
    assert_equal 1, status2
  end

  # --- G9 backward shim: the actions-only shape (intent 342, n2) -------------------

  def write_action_file(name, body)
    dir = File.join(@dir, "actions")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, name), body)
  end

  def test_actions_only_intent_validates
    write_action_file("ACTION_1.md", "# Action 1\nSome legacy prose, no Steps, no Proven by.\n")
    result = WorkGraphValidator.validate(@dir)
    assert result[:ok], result[:errors].inspect
  end

  def test_actions_only_intent_returns_no_errors
    write_action_file("ACTION_1.md", "# Action 1\nlegacy body\n")
    write_action_file("ACTION_2.md", "# Action 2\nlegacy body\n")
    result = WorkGraphValidator.validate(@dir)
    assert_equal [], result[:missing]
    assert_equal [], result[:errors]
    assert result[:ok]
  end

  def test_authored_invalid_graph_still_fails_unchanged
    write_graph("- n1 needs n2\n")
    write_node("n1.md", node: "n1", kind: "work", body: work_body("n1"))
    write_action_file("ACTION_1.md", "# legacy action that must never rescue an authored intent\n")
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert(result[:errors].any? { |e| e.include?("n2") })
  end

  def test_empty_intent_dir_still_missing_graph_section
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert_equal ["graph.md ## Graph section"], result[:missing]
  end

  def test_synthetic_shape_skips_matrix_and_verify_bars
    write_action_file("ACTION_1.md", "# Action 1\nlegacy body, no Steps, no Proven by, no matrix.\n")
    write_action_file("ACTION_2.md", "# Action 2\nlegacy body, no Steps, no Proven by, no matrix.\n")
    write_action_file("ACTION_3.md", "# Action 3\nlegacy body, no Steps, no Proven by, no matrix.\n")
    result = WorkGraphValidator.validate(@dir)
    assert result[:ok], result[:errors].inspect
  end

  def test_malformed_graph_md_does_not_fall_through_to_actions
    File.write(File.join(@dir, "graph.md"), "# Graph: Demo\n\nNo Graph section at all.\n")
    write_action_file("ACTION_1.md", "# legacy action, must not rescue the malformed graph.md\n")
    result = WorkGraphValidator.validate(@dir)
    refute result[:ok]
    assert_equal ["graph.md ## Graph section"], result[:missing]
  end

  def test_cli_exits_zero_on_actions_only_dir
    write_action_file("ACTION_1.md", "# Action 1\nlegacy body\n")
    out, _err, status = run_cli(@dir)
    assert_equal 0, status
    assert_match(/\AOK: /, out)
  end

  # These two exercise validate_actions_shape's structural checks directly,
  # against a hand-built graph the shim's own builder could never mint (it
  # never mints a dangling needs target or a duplicate id), so a future
  # regression in the builder's uniqueness or reference logic is caught
  # rather than the check passing vacuously (spec.md D16).
  def with_stubbed_shim_view(graph)
    original = ActionGraphShim.method(:view)
    ActionGraphShim.define_singleton_method(:view) { |_intent_dir| { graph: graph } }
    yield
  ensure
    ActionGraphShim.define_singleton_method(:view, original)
  end

  def test_synthetic_check_rejects_a_dangling_needs_target
    graph = { nodes: %w[n1 n2], edges: { "n1" => [], "n2" => ["n3"] }, errors: [] }
    with_stubbed_shim_view(graph) do
      result = WorkGraphValidator.validate_actions_shape(@dir)
      refute result[:ok]
      assert(result[:errors].any? { |e| e.include?('"n3"') })
    end
  end

  def test_synthetic_check_rejects_duplicate_ids
    graph = { nodes: %w[n1 n1], edges: { "n1" => [] }, errors: [] }
    with_stubbed_shim_view(graph) do
      result = WorkGraphValidator.validate_actions_shape(@dir)
      refute result[:ok]
      assert_includes result[:errors], "duplicate node ids in synthetic chain"
    end
  end
end
