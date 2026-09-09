# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/node_packet"
require_relative "../scripts/lib/insights"

# Intent 338 (G5), n2: gathering the five blocks from disk. Matrix rows 2.1
# to 2.27 (plus lettered rows) in actions/ACTION_1.md. Hermetic: Dir.mktmpdir
# fixtures, no environment read, no git shell-out unless a spy is injected.
class NodePacketReadersTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("node-packet-readers")
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

  def savepoint_path
    File.join(@dir, "savepoint.md")
  end

  def append_ledger(line)
    existing = File.exist?(savepoint_path) ? File.read(savepoint_path) : ""
    File.write(savepoint_path, existing + line)
  end

  def record_path
    File.join(@dir, "#{File.basename(@dir)}.md")
  end

  def write_record(intent_text: "Demo intent.", decisions: "- D1 pick approach", insights_body: nil, sources: [])
    insights_body ||= "(observations captured throughout — raw material for future intents)\n"
    File.write(record_path, <<~MD)
      ---
      id: "1"
      sources: #{sources.inspect}
      ---

      ## Intent
      #{intent_text}

      ## Context
      Some context prose that must never leak into the record block.

      ### Decisions
      #{decisions}

      ## Outcome
      (pending)

      ## Insights
      #{insights_body}
      ## Links
      - nothing yet, and this must never leak into the record block either
    MD
  end

  def insight_line(text, at: Time.utc(2026, 9, 1, 12, 0, 0), stage: "Exec", author: "tester")
    "#{at.iso8601}#{Insights::SEPARATOR}#{stage}#{Insights::SEPARATOR}#{author} — #{text}\n"
  end

  # --- 2.1-2.3: the node block --------------------------------------------

  def test_an_invalid_node_file_is_an_error_not_an_empty_block
    write_graph("- n1 needs nothing\n")
    File.write(File.join(@dir, "nodes", "n1.md"), "not even frontmatter\n")
    result = NodePacket.node_block(intent_dir: @dir, node: "n1")
    refute result[:ok]
    assert_nil result[:text]
    refute_empty result[:errors]
  end

  def test_a_node_absent_from_the_graph_is_refused
    write_graph("- n1 needs nothing\n")
    write_node("n9")
    result = NodePacket.node_block(intent_dir: @dir, node: "n9")
    refute result[:ok]
    assert_equal :unknown_node, result[:error_kind]
  end

  def test_the_node_block_carries_node_kind_files_and_budget
    write_graph("- n1 needs nothing\n")
    write_node("n1", kind: "work", files: ["a.rb", "b.rb"], budget: 12_345, body: "# n1\nSteps here.\n")
    result = NodePacket.node_block(intent_dir: @dir, node: "n1")
    assert result[:ok]
    assert_includes result[:text], "n1"
    assert_includes result[:text], "work"
    assert_includes result[:text], "a.rb"
    assert_includes result[:text], "b.rb"
    assert_includes result[:text], "12345"
    assert_includes result[:text], "Steps here."
  end

  # --- 2.4-2.6: the node's own ledger lines -------------------------------

  def test_every_transition_line_for_the_node_is_carried_in_file_order
    append_ledger("2026-09-01T00:00:00Z  n1  planned\n")
    append_ledger("2026-09-01T00:01:00Z  n1  running holder=h1 expires=2026-09-01T01:00:00Z packet=abc model=sonnet\n")
    append_ledger("2026-09-01T00:02:00Z  n1  failed_verification gates=lint reason=\"missed a case\"\n")
    text = NodePacket.ledger_lines_block(intent_dir: @dir, node: "n1")
    lines = text.split("\n")
    assert_equal lines.index { |l| l.include?("planned") } < lines.index { |l| l.include?("running") }, true
    assert lines.index { |l| l.include?("running") } < lines.index { |l| l.include?("failed_verification") }
  end

  def test_the_last_failed_verification_line_carries_its_reason
    append_ledger("2026-09-01T00:00:00Z  n1  failed_verification gates=lint reason=\"first mistake\"\n")
    append_ledger("2026-09-01T00:01:00Z  n1  running holder=h1 expires=2026-09-01T01:00:00Z packet=abc model=sonnet\n")
    append_ledger("2026-09-01T00:02:00Z  n1  failed_verification gates=lint reason=\"second mistake\"\n")
    text = NodePacket.ledger_lines_block(intent_dir: @dir, node: "n1")
    assert_includes text, "second mistake"
  end

  def test_a_torn_line_is_marked_torn_and_never_counted_as_evidence
    append_ledger("2026-09-01T00:00:00Z  n1  running holder=h1\n") # missing expires/packet/model: torn
    text = NodePacket.ledger_lines_block(intent_dir: @dir, node: "n1")
    assert_includes text, "torn"
  end

  # --- 2.7-2.8: predecessors -----------------------------------------------

  def test_predecessors_come_from_the_graph_md_edges
    write_graph("- n1 needs n2\n- n2 needs nothing\n")
    File.write(savepoint_path, "2026-09-01T00:00:00Z  n2  done holder=h1 gates=lint commit=abc123\n")
    text = NodePacket.predecessor_block(intent_dir: @dir, node: "n1")
    assert_includes text, "n2"
    assert_includes text, "done"
  end

  def test_only_an_attributed_done_line_counts_as_predecessor_evidence
    write_graph("- n1 needs n2\n- n2 needs nothing\n")
    File.write(savepoint_path, "2026-09-01T00:00:00Z  n2  done gates=lint commit=abc123\n") # no holder=: unattributed
    text = NodePacket.predecessor_block(intent_dir: @dir, node: "n1")
    refute_includes text, "done —"
    assert_includes text, "not yet done"
  end

  # --- 2.9-2.11: the lease --------------------------------------------------

  def test_lease_flags_render_the_lease_block
    text = NodePacket.lease_block(intent_dir: @dir, node: "n1", holder: "auto-abc", expires: "2026-09-01T01:00:00Z",
                                   model: "sonnet")
    assert_includes text, "auto-abc"
    assert_includes text, "sonnet"
  end

  def test_without_flags_the_last_running_line_is_the_lease
    append_ledger("2026-09-01T00:00:00Z  n1  running holder=h1 expires=2026-09-01T01:00:00Z packet=abc model=sonnet\n")
    text = NodePacket.lease_block(intent_dir: @dir, node: "n1")
    assert_includes text, "h1"
    assert_includes text, "sonnet"
  end

  def test_no_lease_renders_lease_none_and_the_stop_directive
    text = NodePacket.lease_block(intent_dir: @dir, node: "n1")
    assert_includes text, "lease: none"
    assert_includes text, NodePacket::STOP_DIRECTIVE
  end

  # --- 2.12-2.14: landed commits ---------------------------------------------

  def test_a_reclaimed_node_carries_the_landed_commits_with_their_diffstat
    append_ledger("2026-09-01T00:00:00Z  n1  reclaimed holder=h1 expired=2026-09-01T01:00:00Z\n")
    spy = ->(repo_dir:, files:) { "abc123 fix thing\n a.rb | 2 +-\n" }
    text = NodePacket.landed_commits_block(intent_dir: @dir, node: "n1", files: ["a.rb"], repo_dir: "/tmp/repo",
                                            git_runner: spy)
    assert_includes text, "abc123"
    assert_includes text, "a.rb | 2 +-"
  end

  def test_a_node_with_no_reclaimed_line_never_calls_the_git_runner
    called = false
    spy = ->(repo_dir:, files:) { called = true; "should never run" }
    result = NodePacket.landed_commits_block(intent_dir: @dir, node: "n1", files: ["a.rb"], repo_dir: "/tmp/repo",
                                              git_runner: spy)
    refute called
    assert_nil result
  end

  def test_a_failing_git_runner_degrades_to_a_note_not_an_exception
    append_ledger("2026-09-01T00:00:00Z  n1  reclaimed holder=h1 expired=2026-09-01T01:00:00Z\n")
    spy = ->(repo_dir:, files:) { raise "git exploded" }
    text = nil
    begin
      text = NodePacket.landed_commits_block(intent_dir: @dir, node: "n1", files: ["a.rb"], repo_dir: "/tmp/repo",
                                              git_runner: spy)
    rescue StandardError
      flunk "landed_commits_block must never raise"
    end
    refute_nil text
    assert_includes text, "unavailable"
  end

  # --- 2.15-2.18a: the record block -------------------------------------------

  def test_the_record_block_carries_intent_decisions_and_insights_only
    write_record(intent_text: "The demo intent text.", decisions: "- D1 first\n- D2 second",
                  insights_body: insight_line("an insight"))
    result = NodePacket.record_block(intent_dir: @dir, kind: "work")
    assert result[:ok]
    assert_includes result[:intent], "The demo intent text."
    assert_equal ["D1 first", "D2 second"], result[:decisions].map { |d| d.strip.sub(/\A-\s*/, "") }
    assert_equal 1, result[:insights].length
    assert_includes result[:insights].first, "an insight"
    refute_includes result[:intent], "must never leak"
  end

  def test_only_the_last_three_insights_are_carried
    body = (1..5).map { |i| insight_line("insight #{i}", at: Time.utc(2026, 9, i, 12, 0, 0)) }.join
    write_record(insights_body: body)
    result = NodePacket.record_block(intent_dir: @dir, kind: "work")
    assert_equal 3, result[:insights].length
    assert_includes result[:insights].last, "insight 5"
    assert_includes result[:insights][0], "insight 3"
  end

  def test_an_entry_keeps_its_continuation_lines_and_three_entries_means_three_prefixes
    body = +""
    body << insight_line("first entry")
    body << "  a continuation line for the first entry\n"
    body << insight_line("second entry")
    body << insight_line("third entry")
    write_record(insights_body: body)
    result = NodePacket.record_block(intent_dir: @dir, kind: "work")
    assert_equal 3, result[:insights].length
    assert_includes result[:insights][0], "a continuation line for the first entry"
    assert_equal 3, result[:insights].count { |e| e.match?(Insights::PREFIX_RE) }
  end

  def test_a_placeholder_only_insights_section_yields_no_entries
    write_record(insights_body: "(observations captured throughout — raw material for future intents)\n")
    result = NodePacket.record_block(intent_dir: @dir, kind: "work")
    assert_empty result[:insights]
  end

  def test_a_verify_nodes_record_block_excludes_the_findings_subsection
    body = +""
    body << insight_line("an insight")
    body << "\n### Findings\n- something the producer noticed\n"
    write_record(insights_body: body)
    result = NodePacket.record_block(intent_dir: @dir, kind: "verify")
    refute(result[:insights].any? { |e| e.include?("something the producer noticed") })
  end

  def test_a_work_nodes_record_block_keeps_the_findings_subsection
    body = +""
    body << insight_line("an insight")
    body << "\n### Findings\n- something the producer noticed\n"
    write_record(insights_body: body)
    result = NodePacket.record_block(intent_dir: @dir, kind: "work")
    joined = result[:insights].join("\n")
    assert_includes joined, "something the producer noticed"
  end

  def test_findings_is_matched_only_under_insights_and_tolerates_a_trailing_qualifier
    body = +""
    body << insight_line("an insight")
    body << "\n### Findings (starting point, from a prior check)\n- drop this under verify\n"
    write_record(intent_text: "Intent text.",
                  decisions: "- D1 pick approach\n\n### Findings\n- this Context finding must survive, it is not under Insights",
                  insights_body: body)
    verify_result = NodePacket.record_block(intent_dir: @dir, kind: "verify")
    refute(verify_result[:insights].any? { |e| e.include?("drop this under verify") })
    # The record block never even reads ## Context, so a "### Findings" living there
    # (as intent 109's record does) is never touched by the Insights-only exclusion rule.
    work_result = NodePacket.record_block(intent_dir: @dir, kind: "work")
    refute(work_result[:decisions].join.include?("this Context finding must survive"))
  end

  # --- 2.19-2.23: the knowledge hop -------------------------------------------

  def write_source(id, outcome: "Outcome text.", decisions: "- SD1 a source decision", sources: [])
    source_dir = File.join(@dir, "..", id)
    source_dir = File.expand_path(source_dir)
    FileUtils.mkdir_p(source_dir)
    File.write(File.join(source_dir, "#{id}.md"), <<~MD)
      ---
      id: "#{id}"
      sources: #{sources.inspect}
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

  def store_dir
    File.dirname(@dir)
  end

  # A real intent record's frontmatter carries a bare-date `created:` field
  # (334 of 449 records in the live store do), which YAML.safe_load rejects
  # by default (Psych::DisallowedClass) unless Date is permitted. Found by
  # the n5 dogfood build against this intent's own record, whose frontmatter
  # has exactly this shape: record_sources silently swallowed the exception
  # and returned [], so the hop was empty for every real intent record.
  def test_record_sources_reads_frontmatter_carrying_a_bare_date
    File.write(record_path, <<~MD)
      ---
      id: "1"
      sources: ["327"]
      created: 2026-09-07
      ---

      ## Intent
      Demo intent.
    MD
    assert_equal ["327"], NodePacket.record_sources(@dir)
  end

  def test_the_hop_is_one_level_and_never_follows_a_sources_sources
    write_source("src-b", outcome: "B outcome text.")
    write_source("src-a", outcome: "A outcome text.", sources: ["src-b"])
    result = NodePacket.hop_block(store_dir: store_dir, sources: ["src-a"], hop_tokens: 2000)
    assert_includes result[:text], "A outcome text."
    refute_includes result[:text], "B outcome text."
  end

  def test_the_hop_carries_only_outcome_and_decisions
    write_source("src-c", outcome: "C outcome.", decisions: "- CD1 a decision")
    result = NodePacket.hop_block(store_dir: store_dir, sources: ["src-c"], hop_tokens: 2000)
    assert_includes result[:text], "C outcome."
    assert_includes result[:text], "CD1 a decision"
    refute_includes result[:text], "Source src-c."
  end

  def test_a_source_without_record_decisions_falls_back_to_its_spec_decisions
    source_dir = write_source("src-d", outcome: "D outcome.", decisions: "")
    File.write(File.join(source_dir, "spec.md"), <<~MD)
      # Spec: D

      ## Decisions
      - D1. the spec decision
    MD
    result = NodePacket.hop_block(store_dir: store_dir, sources: ["src-d"], hop_tokens: 2000)
    assert_includes result[:text], "the spec decision"
  end

  def test_an_unresolvable_source_is_noted_and_never_raises
    result = nil
    begin
      result = NodePacket.hop_block(store_dir: store_dir, sources: ["ghost-999"], hop_tokens: 2000)
    rescue StandardError
      flunk "hop_block must never raise on an unresolvable source"
    end
    assert_includes result[:text], "unresolvable"
  end

  def test_the_hop_is_truncated_at_the_cap_with_a_truncation_note
    write_source("src-e", outcome: "x" * 20_000)
    result = NodePacket.hop_block(store_dir: store_dir, sources: ["src-e"], hop_tokens: 50)
    assert_includes result[:text], "truncat"
    assert_operator result[:tokens], :<=, 60
  end

  def test_a_zero_hop_cap_emits_no_hop_block
    write_source("src-f", outcome: "F outcome.")
    result = NodePacket.hop_block(store_dir: store_dir, sources: ["src-f"], hop_tokens: 0)
    assert_nil result[:text]
    assert_equal 0, result[:tokens]
  end

  # --- 2.24-2.27: where to work -----------------------------------------------

  def test_the_worktree_block_comes_from_the_injected_worktree_reader
    reader = ->(intent_dir:) { { "code" => "/tmp/my-worktree", "code_branch" => "plastic/x", "provisioned" => true } }
    text = NodePacket.worktree_block(intent_dir: @dir, worktree_reader: reader)
    assert_includes text, "/tmp/my-worktree"
    assert_includes text, "plastic/x"
  end

  def test_the_test_command_comes_from_the_project_records_release_verify
    reader = ->(_intent_dir) { "ruby bin/test" }
    text = NodePacket.test_command_block(intent_dir: @dir, project_reader: reader)
    assert_includes text, "ruby bin/test"
  end

  def test_a_missing_project_record_renders_none_recorded
    reader = ->(_intent_dir) { nil }
    text = NodePacket.test_command_block(intent_dir: @dir, project_reader: reader)
    assert_includes text, "none recorded in the project record"
  end

  def test_an_unprovisioned_worktree_renders_a_stop_directive_not_an_empty_path
    reader = ->(intent_dir:) { { "code" => nil, "code_branch" => nil, "provisioned" => false } }
    text = NodePacket.worktree_block(intent_dir: @dir, worktree_reader: reader)
    refute_includes text, "code:  " # never an empty path rendered bare
    assert_includes text, NodePacket::STOP_DIRECTIVE
  end
end
