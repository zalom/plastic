# frozen_string_literal: true

require_relative "../../../test_helper"

# A node move that gives a result writes the node, its run, the documents of the changed files and its work_log line in one transaction.
class WorkLoggedNodesTest < Plastic::TestCase
  include LifecycleHelper

  FINDINGS = "# Findings\n\nThe work showed it.\n"

  def setup
    super
    specified
    cli("intent", "approve", "1")
    cli("node", "add", "1", "Build", "--criterion", KEY)
    cli("node", "claim", "1", "n1")
  end

  def work = Plastic::Graph.open(home: @plastic_home, store: "global", session: "delivery").work

  def dir = retrieval.intent("1").dir

  def heads = store_database.rows("SELECT path, sha256 FROM document_heads WHERE path = 'findings.md'")

  def kinds = retrieval.structure.work_log("1").map(&:kind)

  def refuse_new_heads
    store_database.transaction { |batch| batch.add("CREATE TRIGGER refuse_heads BEFORE INSERT ON document_heads BEGIN SELECT RAISE(ABORT, 'heads refused'); END") }
  end

  def test_done_node_writes_node_run_document_and_log_in_one_transaction
    write("#{dir}/findings.md", FINDINGS)
    work.done_node(intent_id: "1", id: "n1", by: "delivery", findings: "ok", files: [])

    assert_equal "done", retrieval.node("1", "n1").state
    refute_nil retrieval.structure.runs("1").first.ended_at
    assert_equal [{ "path" => "findings.md", "sha256" => Digest::SHA256.hexdigest(FINDINGS) }], heads
    assert_equal 1, kinds.count("done")
  end

  def test_the_files_the_node_read_are_printed_from_the_rows_after_the_move
    write("#{dir}/findings.md", FINDINGS)
    work.done_node(intent_id: "1", id: "n1", by: "delivery", findings: "ok", files: [])

    assert_equal FINDINGS, folder.read("#{dir}/findings.md")
    assert_equal Digest::SHA256.hexdigest(FINDINGS), retrieval.stored.printed.fetch("#{dir}/findings.md")
  end

  def test_a_failing_read_rolls_back_the_node_move
    write("#{dir}/findings.md", FINDINGS)
    refuse_new_heads
    before = kinds

    assert_raises(Plastic::Failed) { work.done_node(intent_id: "1", id: "n1", by: "delivery", findings: "ok", files: []) }
    assert_equal "claimed", retrieval.node("1", "n1").state
    assert_nil retrieval.structure.runs("1").first.ended_at
    assert_empty heads
    assert_empty store_database.rows("SELECT 1 FROM documents WHERE path = 'findings.md'")
    assert_equal before, kinds
  end

  def test_fail_ask_and_impede_read_the_result_too
    { fail_node: [{ reason: "broke" }, "failed"], ask_node: [{ question: "which?" }, "needs_info"], impede_node: [{ reason: "blocked" }, "impeded"] }.each do |move, (fields, state)|
      cli("node", "release", "1", "n1")
      cli("node", "claim", "1", "n1")
      write("#{dir}/findings.md", "# #{move}\n")
      work.public_send(move, intent_id: "1", id: "n1", by: "delivery", files: [], **fields)

      assert_equal state, retrieval.node("1", "n1").state, move.to_s
      assert_equal Digest::SHA256.hexdigest("# #{move}\n"), heads.first.fetch("sha256"), move.to_s
    end
  end

  def test_a_move_another_session_holds_reads_no_file
    write("#{dir}/findings.md", FINDINGS)

    assert_nil work.done_node(intent_id: "1", id: "n1", by: "someone-else", findings: "ok", files: [])
    assert_empty heads
  end

  def test_a_move_with_no_files_option_reads_every_changed_file
    write("#{dir}/findings.md", FINDINGS)
    work.done_node(intent_id: "1", id: "n1", by: "delivery", findings: "ok")

    assert_equal 1, heads.size
  end
end
