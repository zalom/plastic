# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tempfile"

class RetrievalContextResumeTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("plastic-retrieval-resume")
    @home = File.join(@directory, ".plastic")
    @bin = File.expand_path("../../bin/plastic", __dir__)
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_real_cli_resumes_only_the_matching_saved_discovery_context
    command("intent", "new", "Evidence delivery")
    submit_context(first_reference)

    assert_equal "none", command("intent", "discover", "1", "Evidence").fetch("next")
    assert_changed_discovery(command("intent", "discover", "1", "delivery"))
  end

  def test_documented_search_and_document_get_commands_run_against_a_temporary_store
    command("intent", "new", "Evidence delivery")
    reference = first_reference

    document = command("document", "get", reference)
    search = command("search", "Evidence", "--source-project", "global")

    assert_equal reference, document.dig("result", "document", "uri")
    assert_includes search.dig("result", "results").map { |row| row.fetch("uri") }, reference
  end

  private

  def command(*arguments)
    env = { "PLASTIC_HOME" => @home }
    stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, @bin, *arguments, "--json", chdir: @directory)

    assert_equal 0, status.exitstatus, stderr
    JSON.parse(stdout)
  end

  def context_submission(reference)
    { "evidence" => [reference], "facts" => [], "interpretations" => [], "gaps" => [], "rulings" => [] }
  end

  def first_reference
    command("intent", "discover", "1", "Evidence").dig("result", "discovery", "candidates", 0, "uri")
  end

  def submit_context(reference)
    Tempfile.create(["context", ".json"]) do |file|
      file.write(JSON.generate(context_submission(reference)))
      file.flush

      assert_equal "none", command("intent", "context", "1", "--from", file.path).fetch("next")
    end
  end

  def assert_changed_discovery(result)
    assert_equal "plastic intent context 1 --from FILE --project global", result.fetch("next")
    assert_equal "delivery", result.dig("result", "discovery", "query")
  end
end
