# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "time"

require_relative "../scripts/lib/runner_proposals"
require_relative "../scripts/lib/runner_core"
require_relative "../scripts/lib/node_ledger"
require_relative "../scripts/lib/node_file"
require_relative "../scripts/lib/graph_file"
require_relative "../scripts/lib/ready_set"

# RunnerProposals (intent 340, G7, n6): accepts or refuses what an executor
# proposed. Matrix rows 6.8-6.15 in nodes/n6.md.
class RunnerProposalsTest < Minitest::Test
  INTENT_ID = "340"
  INTENT_SLUG = "proposals-fixture"
  REPO = File.expand_path("..", __dir__)
  TEMPLATES_DIR = File.join(REPO, "templates")

  def setup
    @root = Dir.mktmpdir("proposals-intent")
    @dir = File.join(@root, "#{INTENT_ID}--#{INTENT_SLUG}")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
    File.write(File.join(@dir, "#{INTENT_ID}--#{INTENT_SLUG}.md"),
               "---\nid: \"#{INTENT_ID}\"\nintent: t\n---\n\n## Intent\nbody\n")
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  # --- fixture helpers -----------------------------------------------------------

  def write_graph(graph_body, decisions: "- D1 pick an approach", goal: "Ship it.")
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Fixture

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

  def write_work_node(node, files: ["scripts/lib/foo.rb"], budget: 100_000)
    File.write(File.join(@dir, "nodes", "#{node}.md"), <<~MD)
      ---
      node: #{node}
      kind: work
      files: #{files.inspect}
      budget: #{budget}
      ---
      # #{node} - a work node

      ## #{node} failure-mode matrix
      #{MATRIX}
      ## Steps
      1. do it

      ## Proven by
      (filled at close)
    MD
  end

  def write_savepoint(content)
    File.write(File.join(@dir, "savepoint.md"), content)
  end

  def line(subject, state, fields = nil, ts: "2026-01-01T00:00:00Z", **kwfields)
    fields = (fields || {}).merge(kwfields)
    rendered = fields.map { |k, v| "#{k}=#{v}" }.join(" ")
    rendered = " #{rendered}" unless rendered.empty?
    "#{ts}  #{subject}  #{state}#{rendered}\n"
  end

  def graph_path
    File.join(@dir, "graph.md")
  end

  def savepoint_content
    path = File.join(@dir, "savepoint.md")
    File.exist?(path) ? File.read(path) : ""
  end

  def build_context
    loaded = ReadySet.load_graph(@dir)
    RunnerCore::Context.new(
      intent_dir: @dir, intent_id: INTENT_ID, intent_slug: INTENT_SLUG,
      store: nil, plastic_home: @root, session: nil,
      worktree: nil, worktree_branch: nil,
      graph: loaded.merge(ok: true), errors: []
    )
  end

  def accept(**kwargs)
    RunnerProposals.accept(build_context, proposer: "n1", templates_dir: TEMPLATES_DIR, **kwargs)
  end

  # --- 6.8: the runner mints a proposed node's id ------------------------------

  def test_runner_mints_proposed_node_id
    write_graph("- n1 needs nothing\n")
    write_work_node("n1")
    write_savepoint(line("n1", "planned"))

    result = accept(proposed_nodes: [{ "kind" => "work", "title" => "a follow-up", "needs" => [] }])

    assert result[:ok], result.inspect
    assert_equal ["n2"], result[:minted]
  end

  # --- 6.9: the minted id replaces the template's placeholder everywhere -------

  def test_scaffold_substitutes_minted_id_everywhere
    write_graph("- n1 needs nothing\n")
    write_work_node("n1")
    write_savepoint(line("n1", "planned"))

    result = accept(proposed_nodes: [{ "kind" => "work", "title" => "a follow-up", "needs" => [] }])
    id = result[:minted].first

    parsed = NodeFile.parse(File.join(@dir, "nodes", "#{id}.md"))
    assert parsed[:ok], parsed[:errors].inspect
    assert_equal id, parsed[:node]

    sections = NodeFile.split_by_headings(parsed[:body])
    matrix = sections.find { |heading, _| heading.include?(id) && heading.match?(/matrix/i) }
    refute_nil matrix, "the scaffolded matrix heading must carry the minted id, not the template's n1"
    assert_match(/^# #{Regexp.escape(id)} /, parsed[:body])
  end

  # --- 6.9a: files and budget come from the proposal, or the kind's default ----

  def test_scaffold_takes_files_and_budget_from_proposal
    write_graph("- n1 needs nothing\n")
    write_work_node("n1")
    write_savepoint(line("n1", "planned"))

    result = accept(proposed_nodes: [
                       { "kind" => "work", "title" => "explicit files", "needs" => [],
                         "files" => ["scripts/lib/explicit.rb"], "budget" => 5000 },
                       { "kind" => "verify", "title" => "no override", "needs" => [] },
                     ])
    explicit_id, default_id = result[:minted]

    explicit = NodeFile.parse(File.join(@dir, "nodes", "#{explicit_id}.md"))
    assert_equal ["scripts/lib/explicit.rb"], explicit[:files]
    assert_equal 5000, explicit[:budget]

    default = NodeFile.parse(File.join(@dir, "nodes", "#{default_id}.md"))
    template_default = NodeFile.parse(File.join(TEMPLATES_DIR, "node-verify.md"))
    assert_equal template_default[:files], default[:files]
    assert_equal template_default[:budget], default[:budget]
  end

  # --- 6.9b: the full validator re-runs after an accepted proposal -------------

  def test_validator_reruns_after_accepted_proposal
    write_graph("- n1 needs nothing\n")
    write_work_node("n1")
    write_savepoint(line("n1", "planned"))

    calls = []
    spy = lambda do |dir|
      calls << dir
      { ok: true, missing: [], errors: [] }
    end

    result = accept(proposed_nodes: [{ "kind" => "work", "title" => "a follow-up", "needs" => [] }],
                     validator: spy)

    assert result[:ok], result.inspect
    assert_equal [@dir], calls
    assert_equal({ ok: true, missing: [], errors: [] }, result[:validator])
  end

  # --- 6.10: the proposed node is appended to ## Graph, planned ----------------

  def test_proposed_node_appended_to_graph
    write_graph("- n1 needs nothing\n")
    write_work_node("n1")
    write_savepoint(line("n1", "planned"))

    result = accept(proposed_nodes: [{ "kind" => "work", "title" => "a follow-up", "needs" => ["n1"] }])
    id = result[:minted].first

    graph = GraphFile.parse(graph_path)
    assert_includes graph[:graph][:nodes], id
    assert_equal ["n1"], graph[:graph][:edges][id]
    assert_equal "planned", NodeLedger.status_for_content(savepoint_content, id)
  end

  # --- 6.11: refuse a proposed edge whose endpoint does not exist --------------

  def test_edge_to_unknown_node_is_refused
    write_graph("- n1 needs nothing\n")
    write_work_node("n1")
    write_savepoint(line("n1", "planned"))
    before = File.read(graph_path)

    result = accept(proposed_edges: [{ "from" => "n1", "to" => "n99" }])

    refute result[:ok]
    assert_match(/endpoint_unknown/, result[:errors].join)
    assert_equal before, File.read(graph_path)
  end

  # --- 6.12: refuse a proposed edge into a running node ------------------------

  def test_edge_into_running_node_is_refused
    write_graph("- n1 needs nothing\n- n2 needs nothing\n")
    write_work_node("n1")
    write_work_node("n2")
    write_savepoint(line("n1", "running", holder: "h", expires: "2026-01-01T01:00:00Z", packet: "p",
                              model: "sonnet"))
    before = File.read(graph_path)

    result = accept(proposed_edges: [{ "from" => "n1", "to" => "n2" }])

    refute result[:ok]
    assert_match(/head_running/, result[:errors].join)
    assert_equal before, File.read(graph_path)
  end

  # --- 6.13: refuse a proposed edge that makes a cycle -------------------------

  def test_cyclic_edge_is_refused
    write_graph("- n1 needs nothing\n- n2 needs n1\n")
    write_work_node("n1")
    write_work_node("n2")
    write_savepoint(line("n1", "planned") + line("n2", "planned"))
    before = File.read(graph_path)

    result = accept(proposed_edges: [{ "from" => "n1", "to" => "n2" }])

    refute result[:ok]
    assert_match(/would_cycle/, result[:errors].join)
    assert_equal before, File.read(graph_path)
  end

  # --- 6.14: a refusal writes one ledger comment naming the reason ------------

  def test_refusal_records_reason
    write_graph("- n1 needs nothing\n")
    write_work_node("n1")
    write_savepoint(line("n1", "planned"))

    accept(proposed_edges: [{ "from" => "n1", "to" => "n99" }])

    assert_match(/n1: edge n1->n99 refused \(endpoint_unknown\)/, savepoint_content)
  end

  # --- 6.15: nothing is partially written when any part is refused ------------

  def test_refused_proposal_writes_nothing
    write_graph("- n1 needs nothing\n")
    write_work_node("n1")
    write_savepoint(line("n1", "planned"))
    before_graph = File.read(graph_path)
    before_node_files = Dir.glob(File.join(@dir, "nodes", "*.md")).sort

    result = accept(
      proposed_nodes: [{ "kind" => "work", "title" => "a follow-up", "needs" => [] }],
      proposed_edges: [{ "from" => "n1", "to" => "n99" }]
    )

    refute result[:ok]
    assert_equal before_graph, File.read(graph_path)
    assert_equal before_node_files, Dir.glob(File.join(@dir, "nodes", "*.md")).sort
  end
end
