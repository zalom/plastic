# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/cli"

class ResultTest < Minitest::Test
  def result(command = "plastic next")
    Plastic::CLI::Result.new.tap { |answer| answer.offer(command, "a rule") }
  end

  def test_a_scoped_command_keeps_the_project_the_call_named
    assert_equal "plastic node claim 1 n1 --project my\\ app", result("plastic node claim 1 n1").next_command("my app")
  end

  def test_a_command_that_names_its_project_is_left_alone
    assert_equal "plastic next --project a", result("plastic next --project a").next_command("b")
  end

  def test_an_unscoped_command_never_gains_a_project
    assert_equal "plastic help", result("plastic help").next_command("a")
  end

  def test_a_command_the_scoped_list_no_longer_names_never_gains_a_project
    assert_equal "plastic continue", result("plastic continue").next_command("a")
    assert_equal "plastic query x", result("plastic query x").next_command("a")
  end

  def test_with_no_next_step_there_are_no_closing_lines
    assert_empty Plastic::CLI::Result.new.closing_lines("a")
  end

  def test_the_closing_lines_are_next_and_because
    assert_equal ["next: plastic next", "because: a rule"], result.closing_lines(nil)
  end

  def test_the_json_answer_drops_the_label_colon_and_carries_the_lines
    answer = result
    answer.row("node:", "n1")
    answer.line("raw")

    assert_equal({ "result" => { "node" => "n1", "output" => ["raw"] }, "next" => "plastic next", "because" => "a rule" }, answer.document(nil))
  end
end
