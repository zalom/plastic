# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/sync_up"
require_relative "../../../scripts/lib/plastic/commands/sync_down"

class SyncOptionsTest < Plastic::TestCase
  OPTIONS = [{ name: :overwrite, switch: "--overwrite [PATH]", default: false,
               text: "settle conflicts on this side: one record by its path, or every record with no path" },
    { name: :merge, switch: "--merge", default: false, text: "apply the one-sided changes, then list the conflicts" }].freeze

  def test_both_directions_take_the_overwrite_and_merge_switches
    [Plastic::Commands::SyncUp, Plastic::Commands::SyncDown].each do |command|
      description = command.describe.to_h

      assert_equal [OPTIONS, %i[work knowledge references]], [description[:options].reject { |option| option[:name] == :dry_run }.map { |option| option.slice(*OPTIONS.first.keys) },
        description[:writes]]
    end
  end

  def test_each_direction_runs_its_own_workflow
    assert_equal [["sync up", "Read the files changed by hand into rows", %i[code_preview_sync code_sync_up]],
      ["sync down", "Print the rows that changed into files", %i[code_preview_sync code_sync_down]]],
      [Plastic::Commands::SyncUp, Plastic::Commands::SyncDown].map { |command| [*command.describe.to_h.values_at(:name, :summary), command.chain.keys] }
  end

  def test_sync_down_accepts_a_read_only_preview
    result = plastic("sync", "down", "--dry-run", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    assert_includes result.out, "preview"
  end

  def test_both_chains_verify
    assert_equal [true, true], [Plastic::Commands::SyncUp.verify, Plastic::Commands::SyncDown.verify]
  end
end
