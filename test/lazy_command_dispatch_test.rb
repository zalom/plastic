# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "open3"
require "tmpdir"

class LazyCommandDispatchTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_each_dependency_family_dispatches_in_a_fresh_process
    Dir.mktmpdir do |home|
      %w[status intent\ discover\ 1\ term architecture\ status\ --project\ missing hook\ resume].each do |command|
        _stdout, stderr, _status = Open3.capture3(environment(home), File.join(ROOT, "bin", "plastic"), *command.split)

        refute_match(/uninitialized constant/, stderr, command)
      end
    end
  end

  def test_retrieval_context_workflow_runs_through_fresh_cli_processes
    Dir.mktmpdir do |home|
      seed_retrieval_context(home)
      discovered = run_cli(home, "intent", "discover", "1", "selected", "--source-project", "other", "--json")
      reference = JSON.parse(discovered.fetch(:out)).dig("result", "discovery", "candidates", 0, "uri")
      submission = File.join(home, "submission.json")
      File.write(submission, JSON.generate(context_submission(reference)))

      submitted = run_cli(home, "intent", "context", "1", "--from", submission, "--json")
      current = run_cli(home, "intent", "context", "1", "--json")

      assert_equal 0, discovered.fetch(:status).exitstatus, discovered.fetch(:err)
      assert_equal 0, submitted.fetch(:status).exitstatus, submitted.fetch(:err)
      assert_equal 0, current.fetch(:status).exitstatus, current.fetch(:err)
    end
  end

  def test_architecture_commands_load_their_dependencies_in_fresh_cli_processes
    Dir.mktmpdir do |home|
      seed_retrieval_context(home)
      %w[status refresh].each do |command|
        result = run_cli(home, "architecture", command, "--project", "global")

        refute_match(/uninitialized constant/, result.fetch(:err), command)
      end
    end
  end

  private

  def environment(home) = { "HOME" => home, "PLASTIC_HOME" => home, "PLASTIC_TMP" => File.join(home, "tmp") }

  def run_cli(home, *argv)
    out, err, status = Open3.capture3(environment(home), File.join(ROOT, "bin", "plastic"), *argv)
    { out:, err:, status: }
  end

  def seed_retrieval_context(home)
    script = <<~RUBY
      require "plastic"
      require "plastic/graph"
      require "plastic/graph/evidence_writer"
      global = Plastic::Graph.open(home: ARGV.fetch(0), store: "global")
      global.databases.each_value { |database| database.rows("SELECT 1") }
      global.work.write_intent(title: "Selected")
      other = Plastic::Graph.open(home: ARGV.fetch(0), store: "other")
      other.databases.each_value { |database| database.rows("SELECT 1") }
      Plastic::Graph::EvidenceWriter.new(other.databases.fetch(:knowledge), other.retrieval.origin_id).write("1", "evidence.md", "selected evidence")
      other.retrieval.backfill!
    RUBY
    _out, err, status = Open3.capture3({ "RUBYOPT" => "" }, "ruby", "-I", File.join(ROOT, "scripts", "lib"), "-e", script, home)

    assert_predicate status, :success?, err
  end

  def context_submission(reference)
    { "evidence" => [reference], "facts" => [], "interpretations" => [], "gaps" => [], "rulings" => [],
      "architecture" => { "provider" => "external", "revision" => "abc", "coverage" => [], "limitations" => [] } }
  end
end
