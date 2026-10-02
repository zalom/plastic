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

  private

  def rerun_with_fake_mutineer
    seen = nil
    runner = lambda { |*command, chdir:|
      seen = [command, chdir]
      output = command[command.index("--output") + 1]
      File.write(output, JSON.generate({ "survivors" => [], "no_verdict" => [{ "id" => "id2" }] }))
    }
    mutineer = MutationVerdicts::Mutineer.new(["--since", "abc"], root: "/worktree", runner:)
    result = mutineer.rerun("Foo#bar", ["id1", "id2"])

    [seen, *result]
  end
end
