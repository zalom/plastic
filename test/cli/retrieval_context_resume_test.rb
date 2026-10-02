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
    first = command("intent", "discover", "1", "Evidence")
    reference = first.fetch("result").fetch("discovery").fetch("candidates").first.fetch("uri")

    Tempfile.create(["context", ".json"]) do |file|
      file.write(JSON.generate(context_submission(reference)))
      file.flush
      submitted = command("intent", "context", "1", "--from", file.path)
      same = command("intent", "discover", "1", "Evidence")
      changed = command("intent", "discover", "1", "delivery")

      assert_equal "none", submitted.fetch("next")
      assert_equal "none", same.fetch("next")
      assert_equal "plastic intent context 1 --from FILE --project global", changed.fetch("next")
      assert_equal "delivery", changed.fetch("result").fetch("discovery").fetch("query")
    end
  end

  private

  def command(*arguments)
    env = { "PLASTIC_HOME" => @home }
    stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, @bin, *arguments, "--json", chdir: @directory)

    assert_equal 0, status.exitstatus, stderr
    JSON.parse(stdout)
  end

  def context_submission(reference)
    { "evidence" => [reference], "facts" => [], "interpretations" => [], "gaps" => [], "rulings" => [],
      "architecture" => { "provider" => "external", "revision" => "revision", "coverage" => [], "limitations" => [] } }
  end
end
