# frozen_string_literal: true

require "json"
require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/graph/show"
require_relative "../../../../lib/plastic/commands/node/done"

class GraphShowRunsTest < Plastic::TestCase
  include LifecycleHelper

  TIME = "\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ"
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

  def test_json_carries_the_start_end_and_length_of_each_run
    cli("node", "done", "1", "n1", "ok")

    run = JSON.parse(cli("graph", "show", "1", "--json").out).fetch("result").fetch("runs").first

    assert_equal %w[n1 1], run.values_at("node", "number").map(&:to_s)
    assert_match(/\A#{TIME}\z/, run.fetch("started_at"))
    assert_match(/\A#{TIME}\z/, run.fetch("ended_at"))
    assert_kind_of Integer, run.fetch("length_seconds")
  end

  def test_json_of_a_running_run_has_no_end_and_no_length
    run = JSON.parse(cli("graph", "show", "1", "--json").out).fetch("result").fetch("runs").first

    assert_nil run.fetch("ended_at")
    assert_nil run.fetch("length_seconds")
  end
end
