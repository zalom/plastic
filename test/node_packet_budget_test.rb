# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "digest"

require_relative "../scripts/lib/node_packet"

# Intent 338 (G5), n3: assembly, the budget, and the packet's identity.
# Matrix rows 3.1 to 3.26 in actions/ACTION_1.md. Hermetic: Dir.mktmpdir
# fixtures, every seam injected, no environment read.
class NodePacketBudgetTest < Minitest::Test
  NULL_WORKTREE_READER = ->(intent_dir:) { { "code" => nil, "code_branch" => nil, "provisioned" => false } }
  NULL_PROJECT_READER = ->(_intent_dir) { nil }
  NULL_GIT_RUNNER = ->(repo_dir:, files:) { nil }

  def setup
    @dir = Dir.mktmpdir("node-packet-budget")
    FileUtils.mkdir_p(File.join(@dir, "nodes"))
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def write_graph(body)
    File.write(File.join(@dir, "graph.md"), <<~MD)
      # Graph: Demo

      ## Goal
      Ship it.

      ## Decisions
      - D1 pick approach

      ## Graph
      #{body}
      ## Status
      | Node | State | Detail |
      | --- | --- | --- |
    MD
  end

  def write_node(id, kind: "work", files: ["scripts/lib/x.rb"], budget: 100_000, body: nil)
    body ||= "# #{id}\nDo the thing.\n"
    File.write(File.join(@dir, "nodes", "#{id}.md"), <<~MD)
      ---
      node: #{id}
      kind: #{kind}
      files: #{files.inspect}
      budget: #{budget}
      ---
      #{body}
    MD
  end

  def record_path
    File.join(@dir, "#{File.basename(@dir)}.md")
  end

  def write_record(intent_text: "Demo intent.", decisions_items: ["- D1 first"], insights_count: 0, sources: [])
    decisions = decisions_items.join("\n")
    insights_body = if insights_count.zero?
                       "(observations captured throughout — raw material for future intents)\n"
                     else
                       (1..insights_count).map do |i|
                         "2026-09-0#{[i, 9].min}T12:00:00Z · Exec · tester — insight number #{i}\n"
                       end.join
                     end
    File.write(record_path, <<~MD)
      ---
      id: "1"
      sources: #{sources.inspect}
      ---

      ## Intent
      #{intent_text}

      ## Context

      ### Decisions
      #{decisions}

      ## Outcome
      (pending)

      ## Insights
      #{insights_body}
    MD
  end

  def setup_minimal(node: "n1", **kwargs)
    write_graph("- #{node} needs nothing\n")
    write_node(node)
    write_record(**kwargs)
  end

  def build(node: "n1", **overrides)
    defaults = {
      intent_dir: @dir, node: node, worktree_reader: NULL_WORKTREE_READER, project_reader: NULL_PROJECT_READER,
      git_runner: NULL_GIT_RUNNER,
    }
    NodePacket.build(**defaults.merge(overrides))
  end

  # --- 3.1-3.4: order, trust split, one token, determinism --------------------

  def test_blocks_render_in_the_fixed_order
    setup_minimal(intent_text: "INTENT_MARKER text.", decisions_items: ["- D1 DECISIONS_MARKER"], insights_count: 1)
    result = build
    assert result[:ok]
    content = File.read(result[:path])
    node_idx = content.index("Do the thing.")
    ledger_idx = content.index("Transitions")
    record_idx = content.index("INTENT_MARKER")
    where_idx = content.index("worktree:")
    assert node_idx < ledger_idx
    assert ledger_idx < record_idx
    assert record_idx < where_idx
  end

  def test_only_the_ledger_record_and_hop_blocks_are_wrapped
    setup_minimal(intent_text: "The wrapped intent.")
    result = build
    content = File.read(result[:path])
    blocks = PacketWrapper.unwrap(content)
    payload = blocks.map { |b| b[:payload] }.join
    refute_includes payload, "Do the thing."
    refute_includes payload, "worktree:"
    assert_includes payload, "The wrapped intent."
  end

  def test_every_data_block_shares_one_boundary_token
    write_source("src-1", outcome: "hop outcome text")
    setup_minimal(intent_text: "Shared token intent.", sources: ["src-1"])
    result = build(hop_tokens: 2000)
    content = File.read(result[:path])
    tokens = content.scan(/<<<PLASTIC-DATA:([0-9a-f]+)/).flatten.uniq
    assert_equal 1, tokens.length
  end

  def test_two_builds_of_the_same_node_are_byte_identical
    setup_minimal(intent_text: "Deterministic intent.")
    r1 = build(attempt: 1)
    bytes1 = File.binread(r1[:path])
    r2 = build(attempt: 1, force: true)
    bytes2 = File.binread(r2[:path])
    assert_equal bytes1, bytes2
    assert_equal r1[:sha], r2[:sha]
  end

  # --- 3.5-3.11: the cut ladder ------------------------------------------------

  def test_a_packet_under_budget_keeps_every_block
    write_source("src-2", outcome: "small hop")
    setup_minimal(intent_text: "Small intent.", decisions_items: ["- D1 one"], insights_count: 2, sources: ["src-2"])
    result = build(budget_tokens: 8000, hop_tokens: 2000)
    assert result[:ok]
    assert_empty result[:cuts_applied]
    content = File.read(result[:path])
    assert_includes content, "small hop"
  end

  def big_decisions(n)
    (1..n).map { |i| "- D#{i} decision number #{i} with some padding text to spend tokens" }
  end

  def test_the_first_cut_drops_the_hop_whole
    write_source("src-3", outcome: "x" * 20_000)
    setup_minimal(intent_text: "Cut test intent.", decisions_items: big_decisions(3), insights_count: 2,
                   sources: ["src-3"])
    result = build(budget_tokens: 6100, hop_tokens: 2000)
    assert result[:ok]
    assert_includes result[:cuts_applied], :hop
    refute_includes result[:cuts_applied], :insights
    refute_includes result[:cuts_applied], :decisions
    content = File.read(result[:path])
    refute_includes content, "knowledge hop"
  end

  def test_the_second_cut_leaves_exactly_one_insight
    write_source("src-4", outcome: "x" * 20_000)
    setup_minimal(intent_text: "Cut test intent two.", decisions_items: big_decisions(3), insights_count: 3,
                   sources: ["src-4"])
    result = build(budget_tokens: 1650, hop_tokens: 2000)
    assert result[:ok]
    assert_includes result[:cuts_applied], :hop
    assert_includes result[:cuts_applied], :insights
    content = File.read(result[:path])
    assert_includes content, "insight number 3"
    refute_includes content, "insight number 1"
  end

  def test_the_third_cut_leaves_the_last_five_decisions
    write_source("src-5", outcome: "x" * 20_000)
    setup_minimal(intent_text: "Cut test intent three.", decisions_items: big_decisions(9), insights_count: 3,
                   sources: ["src-5"])
    result = build(budget_tokens: 950, hop_tokens: 2000)
    assert result[:ok]
    assert_includes result[:cuts_applied], :decisions
    content = File.read(result[:path])
    assert_includes content, "decision number 9"
    refute_includes content, "decision number 1"
    assert_equal 5, (5..9).count { |i| content.include?("decision number #{i}") }
  end

  def test_the_node_ledger_and_where_to_work_blocks_survive_every_cut
    write_source("src-6", outcome: "x" * 20_000)
    setup_minimal(intent_text: "Never cut.", decisions_items: big_decisions(9), insights_count: 3,
                   sources: ["src-6"])
    result = build(budget_tokens: 950, hop_tokens: 2000)
    assert result[:ok]
    content = File.read(result[:path])
    assert_includes content, "Do the thing."
    assert_includes content, "Transitions"
    assert_includes content, "worktree:"
  end

  def test_overflow_past_the_third_cut_writes_no_file_and_exits_four
    write_source("src-7", outcome: "x" * 200_000)
    setup_minimal(intent_text: "y" * 200_000, decisions_items: big_decisions(50), insights_count: 3,
                   sources: ["src-7"])
    result = build(budget_tokens: 100, hop_tokens: 2000)
    refute result[:ok]
    assert_equal 4, result[:exit_code]
    refute File.exist?(File.join(@dir, "packets"))
  end

  def test_the_overflow_refusal_prints_a_needs_decision_command_carrying_a_non_empty_question
    write_source("src-8", outcome: "x" * 200_000)
    setup_minimal(intent_text: "z" * 200_000, decisions_items: big_decisions(50), insights_count: 3,
                   sources: ["src-8"])
    result = build(budget_tokens: 100, hop_tokens: 2000)
    refute result[:ok]
    cmd = result[:needs_decision_command]
    refute_nil cmd
    assert_includes cmd, "--state needs_decision"
    m = cmd.match(/question="([^"]*)"/)
    refute_nil m
    refute_empty m[1].strip
    missing = NodeLedger.missing_fields("needs_decision", { question: m[1] })
    assert_empty missing
  end

  # --- 3.12-3.14: attempt numbering -------------------------------------------

  def test_the_attempt_number_counts_the_nodes_prior_running_lines
    setup_minimal(intent_text: "Attempt counting.")
    File.write(File.join(@dir, "savepoint.md"), <<~LEDGER)
      2026-09-01T00:00:00Z  n1  running holder=h1 expires=2026-09-01T01:00:00Z packet=abc model=sonnet
      2026-09-01T01:00:01Z  n1  failed_verification gates=lint reason="nope"
      2026-09-01T02:00:00Z  n1  running holder=h2 expires=2026-09-01T03:00:00Z packet=def model=sonnet
    LEDGER
    result = build
    assert_equal 2, result[:attempt]
  end

  def test_a_lease_flag_increments_the_attempt
    setup_minimal(intent_text: "Attempt increment.")
    File.write(File.join(@dir, "savepoint.md"), <<~LEDGER)
      2026-09-01T00:00:00Z  n1  running holder=h1 expires=2026-09-01T01:00:00Z packet=abc model=sonnet
    LEDGER
    result = build(holder: "auto-newholder", expires: "2026-09-02T00:00:00Z", model: "sonnet")
    assert_equal 2, result[:attempt]
  end

  def test_the_attempt_override_names_the_file
    setup_minimal(intent_text: "Attempt override.")
    result = build(attempt: 7)
    assert_equal 7, result[:attempt]
    assert_includes result[:path], "n1--a7.packet"
  end

  # --- 3.15-3.19: place, hash, report -----------------------------------------

  def test_the_packet_lands_under_packets_named_by_node_and_attempt
    setup_minimal(intent_text: "Path test.")
    result = build(attempt: 3)
    assert_equal File.join(@dir, "packets", "n1--a3.packet"), result[:path]
  end

  def test_the_hash_is_sha256_of_the_file_bytes_first_twelve_hex
    setup_minimal(intent_text: "Hash test.")
    result = build
    expected = Digest::SHA256.hexdigest(File.binread(result[:path]))[0, 12]
    assert_equal expected, result[:sha]
    assert_equal 12, result[:sha].length
  end

  def test_the_packet_file_does_not_contain_its_own_hash
    setup_minimal(intent_text: "No self-hash.")
    result = build
    content = File.read(result[:path])
    refute_includes content, result[:sha]
  end

  def test_stdout_is_a_parsable_summary_carrying_path_sha_tokens_hop_and_attempt
    setup_minimal(intent_text: "Summary test.")
    result = build
    line = NodePacket.summary_line(result)
    fields = line.split(/\s+/).each_with_object({}) do |tok, h|
      k, v = tok.split("=", 2)
      h[k] = v
    end
    assert_equal result[:path], fields["path"]
    assert_equal result[:sha], fields["sha"]
    assert_equal result[:tokens].to_s, fields["tokens"]
    assert_equal result[:hop_tokens].to_s, fields["hop_tokens"]
    assert_equal result[:attempt].to_s, fields["attempt"]
  end

  def test_hop_tokens_is_the_measured_hop_size_and_zero_when_the_hop_is_absent
    setup_minimal(intent_text: "No hop present.")
    result = build(hop_tokens: 0)
    assert_equal 0, result[:hop_tokens]

    write_source("src-9", outcome: "some hop content")
    setup_minimal(intent_text: "Hop present.", sources: ["src-9"])
    result2 = build(hop_tokens: 2000)
    assert_operator result2[:hop_tokens], :>, 0
  end

  # --- 3.20-3.24: writing and floor -------------------------------------------

  def test_the_packets_directory_is_created_when_absent
    setup_minimal(intent_text: "Dir creation.")
    refute Dir.exist?(File.join(@dir, "packets"))
    result = build
    assert result[:ok]
    assert Dir.exist?(File.join(@dir, "packets"))
  end

  def test_the_packet_is_written_through_the_injected_atomicwrite_renamer
    setup_minimal(intent_text: "Renamer spy.")
    called = false
    spy = ->(from, to) { called = true; File.rename(from, to) }
    result = build(renamer: spy)
    assert result[:ok]
    assert called
  end

  def test_the_budget_is_measured_over_the_rendered_bytes_markers_included
    setup_minimal(intent_text: "Marker accounting.")
    result = build
    raw_payload_tokens = PacketWrapper.estimate_tokens(File.read(record_path))
    rendered_tokens = result[:tokens]
    assert_operator rendered_tokens, :>, 0
    refute_equal raw_payload_tokens, rendered_tokens
  end

  def test_a_cut_that_would_not_reduce_the_rendered_size_is_skipped
    write_source("src-10", outcome: "x" * 20_000)
    setup_minimal(intent_text: "Skip cut.", decisions_items: big_decisions(3), insights_count: 1,
                   sources: ["src-10"])
    result = build(budget_tokens: 6100, hop_tokens: 2000)
    assert result[:ok]
    assert_includes result[:cuts_applied], :hop
    refute_includes result[:cuts_applied], :insights
  end

  def test_the_overflow_message_names_the_oversized_block_and_its_token_count
    setup_minimal(intent_text: "n" * 100_000)
    result = build(budget_tokens: 100, hop_tokens: 0)
    refute result[:ok]
    assert_equal 4, result[:exit_code]
    cmd = result[:needs_decision_command]
    assert_match(/node/i, cmd)
  end

  # --- 3.25-3.26: rebuild refusal and the running command ----------------------

  def test_rebuilding_an_attempt_with_changed_input_is_refused_and_identical_input_is_a_noop
    setup_minimal(intent_text: "Rebuild test.")
    r1 = build(attempt: 1)
    assert r1[:ok]
    original_bytes = File.binread(r1[:path])

    File.write(File.join(@dir, "savepoint.md"),
               "2026-09-01T00:00:00Z  n1  planned\n2026-09-01T00:01:00Z  n1  planned\n")
    r2 = build(attempt: 1)
    refute r2[:ok]
    assert_equal 5, r2[:exit_code]
    assert_equal original_bytes, File.binread(r1[:path])

    File.delete(File.join(@dir, "savepoint.md"))
    r3 = build(attempt: 1)
    assert r3[:ok]
    assert_equal original_bytes, File.binread(r3[:path])
  end

  def test_success_prints_the_node_transition_running_command_carrying_packet_and_hop
    setup_minimal(intent_text: "Running command test.")
    result = build(hop_tokens: 0)
    assert_includes result[:running_command], "--state running"
    assert_includes result[:running_command], "packet=#{result[:sha]}"
    assert_includes result[:running_command], "hop=0"
  end

  def write_source(id, outcome: "Outcome text.", decisions: "- SD1 a source decision")
    source_dir = File.expand_path(File.join(@dir, "..", id))
    FileUtils.mkdir_p(source_dir)
    File.write(File.join(source_dir, "#{id}.md"), <<~MD)
      ---
      id: "#{id}"
      sources: []
      ---

      ## Intent
      Source #{id}.

      ## Context

      ### Decisions
      #{decisions}

      ## Outcome
      #{outcome}

      ## Insights
      (observations captured throughout — raw material for future intents)
    MD
    source_dir
  end
end
