# frozen_string_literal: true

require_relative "../../../test_helper"

class CommandEnvironmentTest < Plastic::TestCase
  Ancestry = Data.define(:ancestors)

  def session(env, ancestors: [])
    Plastic::CLI::Command::Environment.new(env: { "PLASTIC_HOME" => @plastic_home }.merge(env), input: StringIO.new, out: StringIO.new,
      err: StringIO.new, home: @home, directory: @home, processes: Ancestry.new(ancestors:)).session
  end

  def seed(session_id, started_at)
    Plastic::Graph::Database::Local.new(@plastic_home).transaction do |batch|
      batch.put(:sessions, { session_id:, harness: "x", started_at: })
    end
  end

  NESTED = { "CLAUDE_CODE_SESSION_ID" => "c-1", "CODEX_THREAD_ID" => "x-1" }.freeze

  def test_the_plastic_session_wins_over_the_harness_session
    assert_equal "p-1", session("PLASTIC_SESSION" => "p-1", "CLAUDE_CODE_SESSION_ID" => "c-1")
  end

  def test_a_blank_variable_falls_through_to_the_next
    assert_equal "x-1", session("PLASTIC_SESSION" => " ", "CODEX_THREAD_ID" => "x-1")
  end

  def test_no_session_variable_is_nil
    assert_nil session({})
  end

  def test_two_nested_harnesses_pick_the_session_that_started_last
    seed("c-1", "2026-10-11T10:00:00Z")
    seed("x-1", "2026-10-11T11:00:00Z")

    assert_equal "x-1", session(NESTED)
  end

  def test_with_no_rows_the_nearest_ancestor_harness_picks_the_session
    assert_equal "x-1", session(NESTED, ancestors: %w[zsh codex claude])
  end

  def test_with_nothing_else_the_registry_order_picks_the_session
    assert_equal "c-1", session(NESTED)
  end

  def test_an_environment_made_without_processes_has_none
    assert_nil environment.processes.ancestors.first
  end
end
