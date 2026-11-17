# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/plastic/routine"
require_relative "../../lib/plastic/cli/table"

class RoutineTest < Plastic::TestCase
  def test_a_chain_of_two_code_workflows_prints_next_and_because
    call = plastic("kernel", "two", "ada")

    assert_equal 0, call.code
    assert_equal "hello ada\nnext: plastic kernel two ada\nbecause: greeted ada\n", call.out
    assert_equal "", call.err
  end

  def test_a_tool_that_writes_nothing_keeps_no_command_run_row
    plastic("kernel", "two", "ada")

    assert_nil command_run("kernel two", "")
  end

  def test_an_agent_workflow_hands_off_with_its_steps
    call = plastic("kernel", "draft", "notes", "--dir", @home)
    path = File.join(@home, "notes.md")

    assert_equal 0, call.code
    assert_equal "1. Write the draft to #{path}\nnext: plastic kernel draft notes\n" \
                 "because: the draft for notes is not written yet\n", call.out
    assert_equal "", call.err
  end

  def test_the_hand_off_is_kept_as_an_open_command_run_row
    plastic("kernel", "draft", "notes", "--dir", @home)
    run = command_run("kernel draft", "notes")

    assert_equal "handed_off", run.status
    assert_equal :agent_write_draft, run.at
    assert_equal %i[code_stamp code_find_draft], run.finished
  end

  def test_the_next_call_reads_the_facts_back_and_finishes
    plastic("kernel", "draft", "notes", "--dir", @home)
    stamp = command_run("kernel draft", "notes").facts.fetch(:stamp)
    File.write(File.join(@home, "notes.md"), "draft")
    call = plastic("kernel", "draft", "notes", "--dir", @home)

    assert_call call, code: 0, out: "because: the draft for notes is written, stamped #{stamp}\n"
    assert_equal "finished", command_run("kernel draft", "notes").status
  end

  def test_a_call_after_a_finished_command_run_starts_a_new_one
    File.write(File.join(@home, "notes.md"), "draft")
    plastic("kernel", "draft", "notes", "--dir", @home)
    first = command_run("kernel draft", "notes").facts.fetch(:stamp)
    plastic("kernel", "draft", "notes", "--dir", @home)

    refute_equal first, command_run("kernel draft", "notes").facts.fetch(:stamp)
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
    assert_equal 0, call.code
    assert_equal "", call.err
  end

  def test_a_codex_session_reaches_the_context
    call = plastic("kernel", "who", env: { "PLASTIC_SESSION" => "", "CLAUDE_CODE_SESSION_ID" => "", "CODEX_THREAD_ID" => "cx-1" })

    assert_includes call.out, "session \"cx-1\""
    assert_equal 0, call.code
    assert_equal "", call.err
  end

  def test_the_plastic_session_variable_wins
    call = plastic("kernel", "who", env: { "PLASTIC_SESSION" => "p-1", "CLAUDE_CODE_SESSION_ID" => "cc-1" })

    assert_includes call.out, "session \"p-1\""
    assert_equal 0, call.code
    assert_equal "", call.err
  end

  def test_no_session_reads_as_nil
    call = plastic("kernel", "who")

    assert_equal [0, ""], [call.code, call.err]
    assert_includes call.out, "session nil"
  end
end

Dir[File.join(__dir__, "../../lib/plastic/commands/**/*.rb")].each { |file| require file }

class PrintsDeclarationTest < Minitest::Test
  NO_FILE = {
    "Session::Note" => "its rows are the session ledger, which no file holds",
    "Node::Renew" => "a renewal changes the time of a claim, which no printed file holds",
    "Backup" => "a backup copies the databases, which no printed file holds",
    "Backup::Purge" => "it removes backup records, which no printed file holds",
    "Backup::Restore" => "it restores databases and hands the files to sync down",
    "Sync::Up" => "sync prints through its own plan",
    "Sync::Down" => "sync prints through its own plan"
  }.freeze

  def routines
    Plastic::CLI::TABLE.values.map(&:first).uniq.grep(/\ACommands::/).map { |name| Object.const_get("Plastic::#{name}") }
      .select { |klass| klass < Plastic::Routine }
  end

  def writers = routines.select { |klass| klass.writes.any? }

  def short(klass) = klass.name.delete_prefix("Plastic::Commands::")

  def test_there_are_routines_that_write
    refute_empty writers
  end

  def test_every_routine_that_writes_declares_prints_or_is_named_without_a_file
    missing = writers.reject { |klass| klass.prints.any? || NO_FILE.key?(short(klass)) }.map { |klass| short(klass) }

    assert_empty missing
  end

  def test_the_named_exceptions_are_routines_that_write
    assert_empty NO_FILE.keys - writers.map { |klass| short(klass) }
  end

  def test_prints_takes_only_intent_roadmap_and_index
    error = assert_raises(Plastic::Invalid) { Class.new(Plastic::Routine) { prints :everything } }

    assert_includes error.message, "everything"
  end

  def test_the_detector_sees_a_writer_without_prints
    sample = Class.new(Plastic::Routine) { writes :work }

    assert_empty sample.prints
    assert_predicate sample.writes, :any?
  end
end

class RoutineFailureTest < Plastic::TestCase
  def test_a_refusal_gate_exits_3_with_the_owner_line
    call = plastic("kernel", "gate", "hold")

    assert_call call, code: 3, err: "plastic: refused, the owner holds hold\nThis step belongs to the owner. Stop and ask; do not retry with a flag.\n"
    assert_equal "refused", command_run("kernel gate", nil).status
  end

  def test_a_failure_gate_exits_1_and_names_the_workflow
    call = plastic("kernel", "gate", "break")

    assert_call call, code: 1, err: "plastic: the check broke on break\n"
    assert_equal 1, command_run("kernel gate", nil).exit_code
  end

  def test_a_passing_gate_lets_the_chain_finish
    call = plastic("kernel", "gate", "pass")

    assert_equal 0, call.code
    assert_equal "because: passed pass\n", call.out
    assert_equal "", call.err
  end

  def test_a_step_that_raises_fails_with_the_error
    call = plastic("kernel", "break")

    assert_equal 1, call.code
    assert_equal "plastic: RuntimeError: boom\n", call.err
    assert_equal "", call.out
  end

  def test_a_step_whose_done_check_still_fails_fails_the_call
    call = plastic("kernel", "stuck")

    assert_equal 1, call.code
    assert_equal "plastic: the step ran and its done check still fails\n", call.err
    assert_equal "", call.out
  end

  def test_a_closing_line_with_no_value_fails_the_call
    call = plastic("kernel", "hole")

    assert_equal 1, call.code
    assert_includes call.err, "Plastic::Invalid: no value for missing"
    assert_equal "", call.out
  end

  def test_a_hand_off_that_stops_as_a_failure_exits_1
    call = plastic("kernel", "review")

    assert_equal 1, call.code
    assert_equal "1. Review the change\nbecause: the review is open\n", call.out
    assert_equal "", call.err
  end

  def test_a_database_error_fails_the_call
    @plastic_home = File.join(Dir.mktmpdir, ".plastic")
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "global"))
    File.write(File.join(@plastic_home, "plastic.db"), "not a database")
    call = plastic("kernel", "gate", "pass")

    assert_equal 1, call.code
    assert_includes call.err, "plastic.db"
    assert_equal "", call.out
  end
end
