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
    cli("intent", "start", "1")
    cli("node", "add", "1", "Build", "--criterion", KEY)
    cli("node", "claim", "1", "n1", "--agent", "tester")
  end

  def work = Plastic::Graph.open(home: @plastic_home, store: "global", session: "delivery").work

  def dir = retrieval.intent("1").dir

  def heads = store_database.rows("SELECT path, sha256 FROM document_heads WHERE path = 'outcome.md' AND sha256 = '#{Digest::SHA256.hexdigest(FINDINGS)}'")

  def head_shas = store_database.rows("SELECT sha256 FROM document_heads WHERE path = \x27outcome.md\x27").map { |row| row.fetch("sha256") }

  def kinds = retrieval.structure.work_log("1").map(&:kind)

  def finish(**fields) = work.done_node(intent_id: "1", id: "n1", by: "delivery", findings: "ok", files: [], **fields)

  def run_ended? = !retrieval.structure.runs("1").first.ended_at.nil?

  def state = retrieval.node("1", "n1").state

  def refuse_new_heads
    store_database.transaction { |batch| batch.add("CREATE TRIGGER refuse_heads BEFORE INSERT ON document_heads BEGIN SELECT RAISE(ABORT, 'heads refused'); END") }
  end

  def test_done_node_writes_node_run_document_and_log_in_one_transaction
    write("#{dir}/outcome.md", FINDINGS)
    finish

    assert_equal ["done", true, 1], [state, run_ended?, kinds.count("done")]
    assert_equal [{ "path" => "outcome.md", "sha256" => Digest::SHA256.hexdigest(FINDINGS) }], heads
  end

  def test_the_files_the_node_read_are_printed_from_the_rows_after_the_move
    write("#{dir}/outcome.md", FINDINGS)
    work.done_node(intent_id: "1", id: "n1", by: "delivery", findings: "ok", files: [])

    assert_equal FINDINGS, folder.read("#{dir}/outcome.md")
    assert_equal Digest::SHA256.hexdigest(FINDINGS), retrieval.stored.printed.fetch("#{dir}/outcome.md")
  end

  def test_a_failing_read_rolls_back_the_node_move
    write("#{dir}/outcome.md", FINDINGS)
    refuse_new_heads
    before = kinds

    assert_raises(Plastic::Failed) { finish }
    assert_equal ["claimed", false, before], [state, run_ended?, kinds]
    assert_empty heads
  end

  MOVES = { fail_node: [{ reason: "broke" }, "failed"], ask_node: [{ question: "which?" }, "needs_info"], impede_node: [{ reason: "blocked" }, "impeded"] }.freeze

  def move_a_new_node(move, number)
    cli("node", "add", "1", "More", "--criterion", KEY)
    cli("node", "claim", "1", "n#{number}", "--agent", "tester")
    write("#{dir}/outcome.md", "# #{move}\n")
    work.public_send(move, intent_id: "1", id: "n#{number}", by: "delivery", files: [], **MOVES.fetch(move).first)
  end

  def test_fail_ask_and_impede_read_the_result_too
    MOVES.each_with_index do |(move, (_fields, expected)), index|
      move_a_new_node(move, index + 2)

      assert_equal [expected, true], [retrieval.node("1", "n#{index + 2}").state, head_shas.include?(Digest::SHA256.hexdigest("# #{move}\n"))], move.to_s
    end
  end

  def test_a_move_another_session_holds_reads_no_file
    write("#{dir}/outcome.md", FINDINGS)

    assert_nil work.done_node(intent_id: "1", id: "n1", by: "someone-else", findings: "ok", files: [])
    assert_empty heads
  end

  def test_a_move_with_no_files_option_reads_every_changed_file
    write("#{dir}/outcome.md", FINDINGS)
    work.done_node(intent_id: "1", id: "n1", by: "delivery", findings: "ok")

    assert_equal 1, heads.size
  end
end
