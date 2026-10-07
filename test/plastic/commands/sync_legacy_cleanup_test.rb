# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/sync_up"

# What the first sync of a legacy store removes, when the config asks it to.
class SyncLegacyCleanupTest < Plastic::TestCase
  fixtures :legacy

  def apply = plastic("sync", "up", table: Plastic::CLI::TABLE)

  def remove_after_import = File.write(File.join(@plastic_home, "config.yml"), "migrate:\n  remove_after_import: true\n")

  def test_the_import_keeps_index_md
    apply

    assert folder.exist?("INDEX.md")
  end

  def test_index_md_goes_after_the_import_when_the_flag_is_on
    remove_after_import

    apply

    refute folder.exist?("INDEX.md")
    assert_equal %w[1 1a], retrieval.intents.map(&:intent_id).sort
  end

  def test_a_completed_intent_is_archived_when_the_flag_is_on
    write("store/2--lone/2--lone.md", "---\nid: \"2\"\nintent: \"Stand alone\"\n---\n\n## Intent\nStand alone\n")
    write("INDEX.md", folder.read("INDEX.md").sub("## Completed\n", "## Completed\n- [2 - Stand alone](store/2--lone/2--lone.md)\n"))
    remove_after_import

    call = apply

    assert_includes call.out, "1 archived"
  end

  def test_regular_sync_keeps_source_files_after_import
    apply
    remove_after_import

    apply

    assert folder.exist?("INDEX.md")
  end
end
