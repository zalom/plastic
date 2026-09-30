# frozen_string_literal: true

require_relative "support/kernel"

class RoutineTest < Minitest::Test
  include KernelFixtures::Calls

  def setup = make_home

  def teardown = remove_home

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

  def test_a_refusal_gate_exits_3_with_the_owner_line
    call = plastic("kernel", "gate", "hold")

    assert_equal 3, call.code
    assert_equal "plastic: refused, the owner holds hold\n" \
                 "This step belongs to the owner. Stop and ask; do not retry with a flag.\n", call.err
    assert_equal "refused", routine_run("kernel gate", nil).status
  end

  def test_a_failure_gate_exits_1_and_names_the_workflow
    call = plastic("kernel", "gate", "break")

    assert_equal 1, call.code
    assert_equal "plastic: code_hold, gate: the check broke on break\n", call.err
    assert_equal 1, routine_run("kernel gate", nil).exit_code
  end

  def test_a_passing_gate_lets_the_chain_finish
    call = plastic("kernel", "gate", "pass")

    assert_equal 0, call.code
    assert_equal "next: none\nbecause: passed pass\n", call.out
  end

  def test_a_step_that_raises_fails_with_the_error
    call = plastic("kernel", "break")

    assert_equal 1, call.code
    assert_equal "plastic: code_break, explode: RuntimeError: boom\n", call.err
  end

  def test_a_step_whose_done_check_still_fails_fails_the_call
    call = plastic("kernel", "stuck")

    assert_equal 1, call.code
    assert_equal "plastic: code_stuck, never lands: the step ran and its done check still fails\n", call.err
  end

  def test_a_closing_line_with_no_value_fails_the_call
    call = plastic("kernel", "hole")

    assert_equal 1, call.code
    assert_includes call.err, "code_hole, closing: Plastic::Invalid: no value for missing"
  end

  def test_a_hand_off_that_stops_as_a_failure_exits_1
    call = plastic("kernel", "review")

    assert_equal 1, call.code
    assert_equal "1. Review the change\nnext: none\nbecause: the review is open\n", call.out
  end

  def test_a_chain_that_points_backward_raises_before_any_step
    error = assert_raises(Plastic::Invalid) { plastic("kernel", "backward") }

    assert_includes error.message, "code_greet -> code_stamp points backward"
  end

  def test_verify_runs_once_per_routine
    assert KernelFixtures::TwoStep.verify!
    assert KernelFixtures::TwoStep.verify!
  end

  def test_the_declared_facts_are_arguments_options_and_workflow_facts
    assert_equal %i[name dir stamp draft_path], KernelFixtures::Draft.declared_facts
  end

  def test_the_calling_session_reaches_the_context
    call = plastic("kernel", "who", env: {"PLASTIC_SESSION" => "", "CLAUDE_CODE_SESSION_ID" => "cc-1"})

    assert_includes call.out, "session \"cc-1\""
  end

  def test_the_plastic_session_variable_wins
    call = plastic("kernel", "who", env: {"PLASTIC_SESSION" => "p-1", "CLAUDE_CODE_SESSION_ID" => "cc-1"})

    assert_includes call.out, "session \"p-1\""
  end

  def test_no_session_reads_as_nil
    assert_includes plastic("kernel", "who").out, "session nil"
  end

  def test_a_database_error_fails_the_call
    FileUtils.rm_rf(@plastic_home)
    File.write(@plastic_home, "not a directory")
    call = plastic("kernel", "gate", "pass")

    assert_equal 1, call.code
    assert_includes call.err, "work_graph.db"
  end
end
