# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "stringio"
require "tmpdir"
require "ostruct"
require_relative "../bin/lib/mutation_verdicts"

# The gate's mutation report: reads Mutineer's JSON, re-runs every subject a
# mutant came back without a verdict for, prints what it found, and decides
# whether the step passes. Every test drives this through the injected
# `runner` and `rerun` callables, so Mutineer itself never starts.
class MutationVerdictsTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("mutation-verdicts")
    @path = File.join(@dir, "report.json")
    @out = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def write_report(summary:, survivors: [], no_verdict: [])
    File.write(@path, JSON.generate({ "summary" => summary, "survivors" => survivors, "no_verdict" => no_verdict }))
  end

  def gate(rerun: ->(*) { flunk("rerun must not run") })
    MutationVerdicts::Gate.new(@path, rerun:, out: @out)
  end

  def run(runner:, rerun: ->(*) { flunk("rerun must not run") })
    MutationVerdicts::Run.new(@path, runner:, rerun:, out: @out)
  end

  def test_a_stale_report_is_never_read
    write_report(summary: { "killed" => 93, "survived" => 7 })
    never_writes = -> { ["", OpenStruct.new(success?: true)] }

    error = assert_raises(MutationVerdicts::Decision::Failure) { run(runner: never_writes).call }

    assert_includes error.message, "mutineer failed"
  end

  def test_survivors_are_printed_with_their_diff
    survivor = { "subject" => "Foo#bar", "file" => "lib/foo.rb", "line" => 12, "diff" => "--- a\n+++ b\n" }
    write_report(summary: { "killed" => 10, "survived" => 1 }, survivors: [survivor])

    gate.call

    assert_includes @out.string, "lib/foo.rb:12"
    assert_includes @out.string, "--- a\n+++ b\n"
  end

  def test_mutants_without_a_verdict_are_named
    mutant = { "subject" => "Foo#bar", "file" => "lib/foo.rb", "line" => 12, "id" => "abc" }
    write_report(summary: { "killed" => 10, "survived" => 0 }, no_verdict: [mutant])
    still_unresolved = ->(_subject, _ids) { [{ "abc" => "no_verdict" }, 0.4] }

    assert_raises(MutationVerdicts::Decision::Failure) { gate(rerun: still_unresolved).call }

    assert_includes @out.string, "lib/foo.rb:12"
  end

  def test_the_score_equals_mutineers_when_nothing_is_rerun
    write_report(summary: { "killed" => 93, "survived" => 7, "score" => 93.0 })

    score = gate.call

    assert_in_delta 93.0, score, 0.01
  end

  def test_each_subject_is_rerun_alone_with_the_same_tests
    mutant = { "subject" => "Foo#bar", "file" => "lib/foo.rb", "line" => 12, "id" => "abc" }
    write_report(summary: { "killed" => 10, "survived" => 0 }, no_verdict: [mutant])
    seen = nil
    rerun = lambda { |subject, ids|
      seen = [subject, ids]
      [{ "abc" => "killed" }, 0.3]
    }

    gate(rerun:).call

    assert_equal ["Foo#bar", ["abc"]], seen
  end

  def test_only_ids_without_a_verdict_take_the_rerun_verdict
    mutant = { "subject" => "Foo#bar", "file" => "lib/foo.rb", "line" => 12, "id" => "abc" }
    write_report(summary: { "killed" => 10, "survived" => 0 }, no_verdict: [mutant])
    rerun = ->(_subject, _ids) { [{ "abc" => "killed", "unrelated-id" => "survived" }, 0.3] }

    score = gate(rerun:).call

    assert_in_delta 100.0, score, 0.01
  end

  def test_a_mutant_still_without_a_verdict_fails_and_is_named
    mutant = { "subject" => "Foo#bar", "file" => "lib/foo.rb", "line" => 12, "id" => "abc" }
    write_report(summary: { "killed" => 10, "survived" => 0 }, no_verdict: [mutant])
    rerun = ->(_subject, _ids) { [{ "abc" => "no_verdict" }, 0.3] }

    error = assert_raises(MutationVerdicts::Decision::Failure) { gate(rerun:).call }

    assert_includes error.message, "abc"
  end

  def test_a_failure_before_the_fork_fails_at_once
    mutant = { "file" => "lib/foo.rb", "line" => 12, "id" => "abc", "status" => "errored" }
    write_report(summary: { "killed" => 10, "survived" => 0 }, no_verdict: [mutant])

    error = assert_raises(MutationVerdicts::Decision::Failure) { gate.call }

    assert_includes error.message, "lib/foo.rb:12"
  end

  def test_each_rerun_reports_its_seconds
    mutant = { "subject" => "Foo#bar", "file" => "lib/foo.rb", "line" => 12, "id" => "abc" }
    write_report(summary: { "killed" => 10, "survived" => 0 }, no_verdict: [mutant])
    rerun = ->(_subject, _ids) { [{ "abc" => "killed" }, 1.7] }

    gate(rerun:).call

    assert_includes @out.string, "Foo#bar"
    assert_includes @out.string, "1.7"
  end

  def test_a_mutineer_error_fails_with_its_output
    crashes = -> { ["boom: segmentation fault", OpenStruct.new(success?: false)] }

    error = assert_raises(MutationVerdicts::Decision::Failure) { run(runner: crashes).call }

    assert_includes error.message, "boom: segmentation fault"
  end

  def test_the_score_counts_rerun_verdicts_against_the_threshold
    mutant = { "subject" => "Foo#bar", "file" => "lib/foo.rb", "line" => 12, "id" => "abc" }
    write_report(summary: { "killed" => 1, "survived" => 0 }, no_verdict: [mutant])
    rerun = ->(_subject, _ids) { [{ "abc" => "survived" }, 0.3] }

    error = assert_raises(MutationVerdicts::Decision::Failure) { MutationVerdicts::Gate.new(@path, rerun:, out: @out, threshold: 75).call }

    assert_includes error.message, "threshold"
  end

  def test_no_mutants_passes
    write_report(summary: { "killed" => 0, "survived" => 0 })

    score = gate.call

    assert_in_delta 100.0, score, 0.01
  end
end
