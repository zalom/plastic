# frozen_string_literal: true

require_relative "../../../test_helper"

class CommandInvocationTest < Plastic::TestCase
  class Show < Plastic::CLI::Command
    argument :intent_id, label: "ID", text: "the intent"
  end

  def invocation(*argv) = Plastic::CLI::Command::Invocation.new(argv, "show", Show)

  def test_it_parses_once_against_the_tool
    call = invocation("7")

    assert_same call.parsed, call.parsed
    assert_equal "7", call.parsed[:intent_id]
  end

  def test_the_usage_line_names_the_words_and_the_arguments
    assert_equal "plastic show ID", invocation.usage_line
  end

  def test_the_switches_it_answers
    call = invocation("--json", "--project", "x", "-h")

    assert_predicate call, :json?
    assert_predicate call, :help?
    assert_predicate call, :project_named?
  end

  def test_without_switches_it_answers_none
    call = invocation("7")

    refute_predicate call, :json?
    refute_predicate call, :help?
    refute_predicate call, :project_named?
  end

  def test_it_keeps_its_own_copy_of_the_argv
    argv = ["7"]
    call = Plastic::CLI::Command::Invocation.new(argv, "show", Show)
    argv << "8"

    assert_equal ["7"], call.argv
  end
end
