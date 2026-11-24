# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/resources_homes"
require_relative "../../../../lib/plastic/commands/intent/repair"

# plastic intent repair applies the folder layout to one intent folder or to all of them. Its dry run writes nothing,
# and it refuses an intent that a live driver or node claim holds.
class IntentRepairCommandTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  OTHER = "store/2--beta"
  BETA_MOVE = "moved plan.md to resources/references/plan.md (#{Plastic::Layout.amendment_reason(:move)})".freeze

  def setup
    super
    write_old_layout
    write("#{OTHER}/plan.md", "# Beta plan\n")
    write("store/.sessions/20260912/a.json", "{}\n")
  end

  def repair(*args) = plastic("intent", "repair", "--project", "global", *args, table: Plastic::CLI::TABLE)

  def at(rel) = File.file?(File.join(store_root, rel))

  def drive(intent_id = "1") = store_graphs.work.drive_intent(intent_id:, by: "s-9")

  def claim_node(seen_at)
    store_database.transaction do |batch|
      batch.put(:nodes, { intent_id: "1", id: "n9", state: "claimed", claimed_by: "s-9", claimed_at: seen_at, seen_at:, updated_at: seen_at })
    end
  end

  def test_the_dry_run_leaves_the_home_as_it_was
    before = snapshot(@plastic_home)
    repair("--all", "--dry-run")

    assert_equal before, snapshot(@plastic_home)
  end

  def test_the_dry_run_names_the_moves_the_removals_and_the_store_leftovers
    out = repair("--all", "--dry-run").out

    assert_match(/^preview: would repair #{INTENT}: .*removed delivery\.lock /, out)
    assert_includes out, "preview: would repair #{OTHER}: #{BETA_MOVE}"
    assert_includes out, "preview: remove store/.sessions/"
  end

  def test_the_dry_run_of_one_intent_names_its_changes_and_no_store_leftover
    out = repair("2", "--dry-run").out

    assert_includes out, "preview: would repair #{OTHER}: #{BETA_MOVE}"
    refute_includes out, "store/.sessions/"
  end

  def test_the_dry_run_of_an_intent_with_nothing_to_change_says_so
    repair("2")

    assert_includes repair("2", "--dry-run").out, "preview: nothing to change"
  end

  def test_an_id_or_all_is_needed_and_not_both
    assert_equal [2, 2], [repair.code, repair("1", "--all").code]
  end

  def test_a_repair_of_one_intent_leaves_the_others_and_the_store_leftovers
    result = repair("1")

    assert_equal [0, true, true], [result.code, at("#{OTHER}/plan.md"), File.directory?(File.join(store_root, "store/.sessions"))]
    assert at("#{INTENT}/resources/references/plan.md")
  end

  def test_an_intent_a_live_driver_holds_is_refused_and_nothing_moves
    drive
    before = intent_files
    result = repair("1")

    assert_equal [3, before], [result.code, intent_files]
    assert_includes result.err, "held #{INTENT}"
  end

  def test_all_repairs_the_free_intents_names_the_held_and_exits_3
    claim_node(Plastic.timestamp(Time.now))
    result = repair("--all")

    assert_equal [3, true, true], [result.code, at("#{INTENT}/plan.md"), at("#{OTHER}/resources/references/plan.md")]
    assert_includes result.err, "held #{INTENT}"
  end

  def test_the_dry_run_of_a_held_intent_exits_3_too
    drive

    assert_equal 3, repair("--all", "--dry-run").code
  end

  def test_a_lapsed_node_claim_holds_nothing
    claim_node(Plastic.timestamp(Time.now - (20 * 60)))

    assert_equal [0, true], [repair("1").code, at("#{INTENT}/resources/references/plan.md")]
  end

  def test_all_removes_the_store_leftovers
    out = repair("--all").out

    assert_includes out, "removed store/.sessions/"
    refute File.directory?(File.join(store_root, "store/.sessions"))
  end

  def test_a_second_run_says_there_is_nothing_to_repair
    repair("--all")

    assert_includes repair("--all").out, "repaired: nothing to change"
  end

  def test_the_command_backs_up_first_and_says_it_writes_amended_lines
    command = Plastic::Commands::Intent::Repair

    assert_equal [true, true], [command.backs_up_first?, command.changes.fetch(:work).include?("amended")]
  end

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
