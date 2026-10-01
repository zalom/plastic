# frozen_string_literal: true

require_relative "../test_helper"

class RoutineRunTest < Plastic::TestCase
  def fresh = Plastic::RoutineRun.fresh("intent end", "7")

  def test_a_fresh_routine_run_is_running_with_nothing_found
    run = fresh

    assert_equal ["running", {}, [], nil], [run.status, run.facts, run.finished, run.at]
    assert_equal run.started_at, run.updated_at
  end

  def test_a_routine_run_needs_every_field
    error = assert_raises(ArgumentError) { Plastic::RoutineRun.new(tool: "x") }

    assert_includes error.message, "a routine run needs subject, at"
  end

  def test_the_key_is_the_tool_and_the_subject
    assert_equal "intent end 7", fresh.key
    assert_equal "status", Plastic::RoutineRun.fresh("status", nil).key
  end

  def test_advance_records_the_finished_workflow_once
    run = fresh.advance(:code_a, :code_b).advance(:code_a, :code_c)

    assert_equal [[:code_a], :code_c, "running"], [run.finished, run.at, run.status]
  end

  def test_every_status_but_finished_is_open
    %w[running handed_off failed refused].each do |status|
      assert_predicate Plastic::RoutineRun.from_h(fresh.to_h.merge(status:)), :open?
    end
    refute_predicate Plastic::RoutineRun.from_h(fresh.to_h.merge(status: "finished")), :open?
  end

  def test_closing_on_finished_keeps_next_and_because
    run = fresh.close(Plastic::Finished.new(next_command: "plastic next", because: "done"), { id: "7" })

    assert_equal ["finished", "plastic next", "done", 0, { id: "7" }],
      [run.status, run.next_command, run.because, run.exit_code, run.facts]
  end

  def test_closing_on_a_hand_off_is_handed_off
    value = Plastic::HandedOff.new(steps: ["x"], next_command: "plastic again", because: "left", exit_code: 1)

    assert_equal ["handed_off", 1], fresh.close(value, {}).then { |run| [run.status, run.exit_code] }
  end

  def test_closing_on_a_failure_keeps_the_message_as_because
    run = fresh.close(Plastic::Failed.new(:code_a, "step", "broke"), {})

    assert_equal ["failed", nil, "code_a, step: broke", 1], [run.status, run.next_command, run.because, run.exit_code]
  end

  def test_closing_on_a_refusal_is_refused
    run = fresh.close(Plastic::Refused.new(:code_a, "owner"), {})

    assert_equal ["refused", "owner", 3], [run.status, run.because, run.exit_code]
  end

  def test_from_h_reads_string_keys_back_into_symbols
    hash = fresh.advance(:code_a, :code_b).to_h.transform_keys(&:to_s)
    hash["facts"] = { "id" => "7" }
    hash["finished"] = ["code_a"]
    hash["at"] = "code_b"
    run = Plastic::RoutineRun.from_h(hash)

    assert_equal [{ id: "7" }, [:code_a], :code_b], [run.facts, run.finished, run.at]
  end

  def test_from_h_keeps_a_nil_at
    assert_nil Plastic::RoutineRun.from_h(fresh.to_h).at
  end

  def test_to_h_lists_the_fields_in_order
    assert_equal Plastic::RoutineRun::FIELDS, fresh.to_h.keys
  end
end
