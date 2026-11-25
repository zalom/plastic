# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/store/sync/up"
require_relative "../../../lib/plastic/commands/store/sync/down"

class SyncOptionsTest < Plastic::TestCase
  MERGE = { name: :merge, switch: "--merge", default: false, text: "apply the one-sided changes, then list the conflicts" }.freeze
  OVERWRITE = {
    up: "read the file of the path into rows, or every file with no path",
    down: "print the rows of the path over its file, or every record with no path"
  }.freeze

  def options_of(command) = command.options.map(&:to_h).reject { |option| option[:name] == :dry_run }.map { |option| option.slice(:name, :switch, :default, :text) }

  def expected(direction)
    [{ name: :overwrite, switch: "--overwrite [PATH]", default: false, text: OVERWRITE.fetch(direction) }, MERGE]
  end

  def test_sync_up_says_that_overwrite_reads_files_into_rows
    assert_equal [expected(:up), %i[work knowledge retrieval]], [options_of(Plastic::Commands::Store::Sync::Up), Plastic::Commands::Store::Sync::Up.writes]
  end

  def test_sync_down_says_that_overwrite_prints_rows_over_files
    assert_equal [expected(:down), %i[work knowledge retrieval]], [options_of(Plastic::Commands::Store::Sync::Down), Plastic::Commands::Store::Sync::Down.writes]
  end

  def test_each_direction_runs_its_own_workflow
    assert_equal [["store sync up", "Read the files changed by hand into rows", %i[code_preview_sync code_sync_up]],
      ["store sync down", "Write the rows that changed into files", %i[code_preview_sync_down code_sync_down]]],
      [Plastic::Commands::Store::Sync::Up, Plastic::Commands::Store::Sync::Down].map { |command| [command.tool_name, Plastic::CLI::TABLE.dig(command.tool_name, 1), command.chain.keys] }
  end

  def test_sync_down_accepts_a_read_only_preview
    result = plastic("store", "sync", "down", "--dry-run", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code, [result.out, result.err].inspect
    assert_includes result.out, "preview"
  end

  # A preview copies committed files, so it runs in a home of its own.
  def test_sync_down_preview_preserves_a_populated_store
    with_home do |home|
      assert_equal 0, call_in(home, "intent", "new", "Preview target").code
      before = snapshot(home)
      result = call_in(home, "store", "sync", "down", "--dry-run")

      assert_equal 0, result.code, [result.out, result.err].inspect
      assert_equal before, snapshot(home)
    end
  end

  def test_both_sync_chains_pass_verify
    assert_equal [true, true], [Plastic::Commands::Store::Sync::Up.verify, Plastic::Commands::Store::Sync::Down.verify]
  end
end
