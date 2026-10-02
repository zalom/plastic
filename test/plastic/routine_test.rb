# frozen_string_literal: true

require_relative "../test_helper"

class RoutineTest < Plastic::TestCase
  def test_a_chain_of_two_code_workflows_prints_next_and_because
    call = plastic("kernel", "two", "ada")

    assert_equal 0, call.code
    assert_equal "hello ada\nnext: plastic kernel two ada\nbecause: greeted ada\n", call.out
  end

  def test_a_tool_that_writes_nothing_keeps_no_routine_run_row
    plastic("kernel", "two", "ada")

    assert_nil routine_run("kernel two", "ada")
  end

  def test_an_agent_workflow_hands_off_with_its_steps
    call = plastic("kernel", "draft", "notes", "--dir", @home)
    path = File.join(@home, "notes.md")

    assert_equal 0, call.code
    assert_equal "1. Write the draft to #{path}\nnext: plastic kernel draft notes\n" \
                 "because: the draft for notes is not written yet\n", call.out
  end

  def test_the_hand_off_is_kept_as_an_open_routine_run_row
    plastic("kernel", "draft", "notes", "--dir", @home)
    run = routine_run("kernel draft", "notes")

    assert_equal "handed_off", run.status
    assert_equal :agent_write_draft, run.at
    assert_equal %i[code_stamp code_find_draft], run.finished
  end

  def test_the_next_call_reads_the_facts_back_and_finishes
    plastic("kernel", "draft", "notes", "--dir", @home)
    stamp = routine_run("kernel draft", "notes").facts.fetch(:stamp)
    File.write(File.join(@home, "notes.md"), "draft")
    call = plastic("kernel", "draft", "notes", "--dir", @home)

    assert_equal 0, call.code
    assert_equal "next: none\nbecause: the draft for notes is written, stamped #{stamp}\n", call.out
    assert_equal "finished", routine_run("kernel draft", "notes").status
  end

  def test_a_call_after_a_finished_routine_run_starts_a_new_one
    File.write(File.join(@home, "notes.md"), "draft")
    plastic("kernel", "draft", "notes", "--dir", @home)
    first = routine_run("kernel draft", "notes").facts.fetch(:stamp)
    plastic("kernel", "draft", "notes", "--dir", @home)

    refute_equal first, routine_run("kernel draft", "notes").facts.fetch(:stamp)
  end

  def test_a_chain_that_points_backward_raises_before_any_step
    error = assert_raises(Plastic::Invalid) { plastic("kernel", "backward") }

    assert_includes error.message, "code_greet -> code_stamp points backward"
  end

  def test_verify_runs_once_per_routine
    assert Fixtures::TwoStep.verify
    assert Fixtures::TwoStep.verify
  end

  def test_the_declared_facts_are_arguments_options_and_workflow_facts
    assert_equal %i[name dir stamp draft_path], Fixtures::Draft.declared_facts
  end

  def test_the_calling_session_reaches_the_context
    call = plastic("kernel", "who", env: { "PLASTIC_SESSION" => "", "CLAUDE_CODE_SESSION_ID" => "cc-1" })

    assert_includes call.out, "session \"cc-1\""
  end

def test_a_codex_session_reaches_the_context
  call = plastic("kernel", "who", env: { "PLASTIC_SESSION" => "", "CLAUDE_CODE_SESSION_ID" => "", "CODEX_THREAD_ID" => "cx-1" })

  assert_includes call.out, "session \"cx-1\""
end

  def test_the_plastic_session_variable_wins
    call = plastic("kernel", "who", env: { "PLASTIC_SESSION" => "p-1", "CLAUDE_CODE_SESSION_ID" => "cc-1" })

    assert_includes call.out, "session \"p-1\""
  end

  def test_no_session_reads_as_nil
    assert_includes plastic("kernel", "who").out, "session nil"
  end
end
