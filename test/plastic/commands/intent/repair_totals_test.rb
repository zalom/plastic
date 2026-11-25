# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/resources_homes"
require_relative "../../../../lib/plastic/commands/intent/repair"

# plastic intent repair prints its totals, which count the intent folders and their changes apart, and lists each link
# it leaves as it is only when --links-left asks for them.
class IntentRepairTotalsTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  def setup
    super
    write_old_layout
    write("store/2--beta/plan.md", "# Beta plan\n")
  end

  def repair(*args) = plastic("intent", "repair", "--project", "global", *args, table: Plastic::CLI::TABLE)

  def test_the_dry_run_counts_the_folders_and_the_changes_and_not_each_link_left
    out = repair("--all", "--dry-run").out

    assert_match(/^preview: 2 intent folders, \d+ changes \(/, out)
    refute_includes out, "preview: link left as it is"
  end

  def test_links_left_lists_each_link_left_as_it_is
    result = repair("--all", "--dry-run", "--links-left")

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "preview: link left as it is #{INTENT}/resources/notes.md: missing.md"
  end

  def test_the_repair_prints_the_count_of_the_links_it_left_and_not_each_one
    out = repair("--all").out

    assert_match(/^repaired: 2 intent folders, .*1 link left as it is, which --links-left lists/, out)
    refute_includes out, "link left as it is #{INTENT}"
  end
end
