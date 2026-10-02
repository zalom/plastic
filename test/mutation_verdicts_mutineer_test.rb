# frozen_string_literal: true

require "minitest/autorun"
require "json"
require_relative "../bin/lib/mutation_verdicts"

# The gate's own collaborator with the real Mutineer: every test drives it
# through an injected `runner`, so a unit test never shells out, and asserts
# the exact argv Mutineer would see for a first run and for a re-run.
class MutationVerdictsMutineerTest < Minitest::Test
  def test_call_builds_the_first_run_argv
    seen = nil
    runner = ->(*command, chdir:) { seen = [command, chdir] }
    mutineer = MutationVerdicts::Mutineer.new(["--since", "abc"], root: "/worktree", runner:)

    mutineer.call("/tmp/mutation_report.json")

    assert_equal ["bundle", "exec", "mutineer", "run", "--since", "abc", "--format", "json", "--output", "/tmp/mutation_report.json"], seen.first
    assert_equal "/worktree", seen.last
  end

  def test_rerun_builds_the_only_jobs_one_argv
    seen, = rerun_with_fake_mutineer
    output = seen.first[seen.first.index("--output") + 1]

    assert_equal ["bundle", "exec", "mutineer", "run", "--since", "abc", "--only", "Foo#bar", "--jobs", "1", "--format", "json", "--output", output],
      seen.first
    assert_equal "/worktree", seen.last
  end

  def test_rerun_reads_its_own_report_for_the_requested_ids
    _, verdicts, seconds = rerun_with_fake_mutineer

    assert_equal({ "id1" => "killed", "id2" => "no_verdict" }, verdicts)
    assert_kind_of Numeric, seconds
  end

  def test_an_unreported_id_has_no_verdict
    report = { "survivors" => [], "no_verdict" => [], "summary" => { "killed" => 1 } }

    assert_equal({ "absent" => "no_verdict" }, MutationVerdicts::Mutineer.verdicts_of(report, ["absent"]))
  end

  def test_an_uncovered_id_is_never_counted_as_killed
    report = { "survivors" => [], "no_verdict" => [], "no_coverage" => [{ "id" => "uncovered" }] }

    assert_equal({ "uncovered" => "no_verdict" }, MutationVerdicts::Mutineer.verdicts_of(report, ["uncovered"]))
  end

  def test_a_failed_rerun_rejects_even_a_written_report
    runner = lambda { |*command, **|
      File.write(command[command.index("--output") + 1], JSON.generate({ "survivors" => [], "no_verdict" => [] }))
      ["rerun failed", Struct.new(:success?).new(false)]
    }

    error = assert_raises(MutationVerdicts::Decision::Failure) do
      MutationVerdicts::Mutineer.new([], runner:).rerun("Foo#bar", ["id1"])
    end

    assert_includes error.message, "rerun failed"
  end

  private

  def rerun_with_fake_mutineer
    seen = nil
    runner = lambda { |*command, chdir:|
      seen = [command, chdir]
      output = command[command.index("--output") + 1]
      File.write(output, JSON.generate({ "killed" => [{ "id" => "id1" }], "survivors" => [], "no_verdict" => [{ "id" => "id2" }] }))
      ["", Struct.new(:success?).new(true)]
    }
    mutineer = MutationVerdicts::Mutineer.new(["--since", "abc"], root: "/worktree", runner:)
    result = mutineer.rerun("Foo#bar", ["id1", "id2"])

    [seen, *result]
  end
end
