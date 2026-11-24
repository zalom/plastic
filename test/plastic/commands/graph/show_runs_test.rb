# frozen_string_literal: true

require "json"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/graph/show"
require_relative "../../../../lib/plastic/commands/node/done"

class GraphShowRunsTest < Plastic::TestCase
  include LifecycleHelper

  TIME = "\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d(?:Z|[+-]\\d\\d:\\d\\d)"
  LENGTH = "(under 1s|\\d+s|\\d+m \\d+s)"

  def setup
    super
    specified
    cli("intent", "approve", "1")
    cli("intent", "start", "1")
    cli("node", "add", "1", "Build", "--criterion", KEY)
    cli("node", "claim", "1", "n1", "--agent", "tester")
  end

  def test_a_run_with_no_end_shows_its_start_and_says_running
    assert_match(/^run: n1 #1 agent tester, .*open; started #{TIME}, running$/, cli("graph", "show", "1").out)
  end

  def test_a_finished_run_shows_its_start_end_and_length
    cli("node", "done", "1", "n1", "ok")

    assert_match(/^run: n1 #1 agent tester, .*done; started #{TIME}, ended #{TIME}, length #{LENGTH}/, cli("graph", "show", "1").out)
  end

  def test_json_carries_the_start_and_end_of_each_run
    cli("node", "done", "1", "n1", "ok")

    run = runs_json.first

    assert_match(/\A#{TIME}\z/, run.fetch("started_at"))
    assert_match(/\A#{TIME}\z/, run.fetch("ended_at"))
  end

  def test_json_carries_the_length_in_seconds_of_a_finished_run
    cli("node", "done", "1", "n1", "ok")

    assert_kind_of Integer, runs_json.first.fetch("length_seconds")
  end

  def test_the_screen_and_json_show_the_same_times_in_the_machine_zone
    cli("node", "done", "1", "n1", "ok")
    stored = store_graphs.databases.fetch(:store).row("SELECT started_at FROM runs").fetch("started_at")

    assert_equal Plastic.local(stored), runs_json.first.fetch("started_at")
    assert_includes cli("graph", "show", "1").out, "started #{Plastic.local(stored)}"
  end

  def test_the_length_comes_from_the_stored_times
    cli("node", "done", "1", "n1", "ok")
    row = store_graphs.databases.fetch(:store).row("SELECT started_at, ended_at FROM runs")

    assert_equal Plastic::Workflows::RunTimes.seconds(row.fetch("started_at"), row.fetch("ended_at")), runs_json.first.fetch("length_seconds")
  end

  def runs_json = JSON.parse(cli("graph", "show", "1", "--json").out).fetch("result").fetch("runs")

  def test_json_of_a_running_run_has_no_end_and_no_length
    run = runs_json.first

    assert_nil run.fetch("ended_at")
    assert_nil run.fetch("length_seconds")
  end
end
