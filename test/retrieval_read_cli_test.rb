# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"

class RetrievalReadCliTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_backup_loads_its_writer_in_a_fresh_cli_process
    in_home do |home|
      assert_success run_cli(home, "intent", "new", "Backup target")
      backup = run_cli(home, "backup")

      assert_success backup
      assert_match(/backup: .*\.tar\.gz/, backup.fetch(:out))
    end
  end

  def test_search_reads_the_index_in_a_fresh_cli_process
    in_home do |home|
      assert_success run_cli(home, "intent", "new", "Search target")
      search = run_cli(home, "search", "Search", "--json")

      assert_success search
      assert_includes JSON.parse(search.fetch(:out)).dig("result", "results").map { |row| row.fetch("store") }, "global"
    end
  end

  private

  def in_home = Dir.mktmpdir { |home| yield home }

  def run_cli(home, *argv)
    out, err, status = Open3.capture3(environment(home), File.join(ROOT, "bin", "plastic"), *argv)
    { out:, err:, status: }
  end

  def environment(home) = { "PLASTIC_HOME" => home, "PLASTIC_TMP" => File.join(home, "tmp") }

  def assert_success(result) = assert_equal(0, result.fetch(:status).exitstatus, result.fetch(:err))
end
