# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "stringio"
require "tmpdir"
require "ostruct"
require_relative "../bin/lib/mutation_verdicts"

# The full run and the gate of the mutation step when the report is missing or its runner succeeded.
class MutationVerdictsRunTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("mutation-run")
    @path = File.join(@dir, "report.json")
    @out = StringIO.new
  end

  def teardown = FileUtils.remove_entry(@dir)

  def run_with(runner) = MutationVerdicts::Run.new(@path, runner:, rerun: ->(*) { flunk("rerun must not run") }, out: @out)

  def test_a_missing_report_fails_by_its_path
    gate = MutationVerdicts::Gate.new(@path, rerun: ->(*) { flunk("rerun must not run") }, out: @out)
    error = assert_raises(MutationVerdicts::Decision::Failure) { gate.call }

    assert_includes error.message, "missing mutation report: #{@path}"
  end

  def test_a_full_run_gates_the_report_its_runner_wrote
    runner = lambda do
      File.write(@path, JSON.generate({ "summary" => { "killed" => 3, "survived" => 1 }, "survivors" => [], "no_verdict" => [] }))
      ["", OpenStruct.new(success?: true)]
    end

    assert_in_delta 75.0, run_with(runner).call, 0.01
  end

  def test_a_successful_runner_that_wrote_no_report_fails_with_its_output
    runner = -> { ["wrote nothing", OpenStruct.new(success?: true)] }
    error = assert_raises(MutationVerdicts::Decision::Failure) { run_with(runner).call }

    assert_includes error.message, "wrote nothing"
  end
end
