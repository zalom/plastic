# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "stringio"
require "tmpdir"
require "ostruct"
require_relative "../bin/lib/mutation_verdicts"

# The command line of the gate's mutation step: it reads the words verify-change passes, hands the words
# after "--" to Mutineer and turns a failed gate into exit code 1 on standard error.
class MutationVerdictsCliTest < Minitest::Test
  # Stands in for Mutineer: writes the report it is given, or none.
  class FakeMutineer
    attr_reader :args

    def initialize(args, summary)
      @args = args
      @summary = summary
    end

    def call(output)
      File.write(output, JSON.generate({ "summary" => @summary, "survivors" => [], "no_verdict" => [] })) if @summary
      ["", OpenStruct.new(success?: true)]
    end

    def rerun(_subject, _ids) = [{}, 0.0]
  end

  def setup
    @dir = Dir.mktmpdir("mutation-cli")
    @out = StringIO.new
    @err = StringIO.new
  end

  def teardown = FileUtils.remove_entry(@dir)

  def cli(summary, words: ["run"])
    @made = nil
    mutineer = ->(args) { @made = FakeMutineer.new(args, summary) }
    argv = [*words, "--output", File.join(@dir, "report.json"), "--threshold", "75", "--", "lib/a.rb", "--test", "test/a_test.rb"]
    MutationVerdicts::Cli.new(argv, out: @out, err: @err, mutineer:)
  end

  def test_a_passing_gate_exits_zero_and_hands_the_words_after_the_double_dash_to_mutineer
    code = cli({ "killed" => 4, "survived" => 0 }).call

    assert_equal [0, ["lib/a.rb", "--test", "test/a_test.rb"], ""], [code, @made.args, @err.string]
    assert_includes @out.string, "Mutation score: 100.0%"
  end

  def test_the_leading_run_word_is_optional
    assert_equal 0, cli({ "killed" => 4, "survived" => 0 }, words: []).call
  end

  def test_a_failing_gate_exits_one_with_its_reason_on_standard_error
    code = cli({ "killed" => 1, "survived" => 3 }).call

    assert_equal 1, code
    assert_includes @err.string, "under the 75% threshold"
  end

  def test_a_run_that_wrote_no_report_exits_one
    assert_equal 1, cli(nil).call
  end
end
