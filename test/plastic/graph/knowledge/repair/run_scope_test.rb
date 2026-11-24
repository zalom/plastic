# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/repair/run"
require_relative "../../../../test_helpers/resources_homes"

# A repair changes only the folders it names, never a held one, removes the old files with their rows, and turns each
# entry of revisions.md into an amended line with its own time.
class RepairRunScopeTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  OTHER = "store/2--beta"
  REVISIONS = "# Revisions\n\n## Revision v1 - 2026-08-30-09:15\n\nThe first change.\n\n## Revision v2 - 2026-09-01\n\nThe second.\n"

  def folder = Plastic::Graph::Knowledge::StoreFolder.new(store_root)

  def repair(**scope) = Plastic::Graph::Knowledge::Repair::Run.new(folder, store_graphs, zone: "+00:00", **scope).call

  def at(rel) = File.file?(File.join(store_root, rel))

  def amended = store_database.rows("SELECT \"at\", text FROM work_log WHERE kind = 'amended' ORDER BY position").map(&:values)

  def close = store_database.transaction { |batch| batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = '1'") }

  def setup
    super
    write_old_layout
    write("#{OTHER}/plan.md", "# Beta plan\n")
  end

  def test_a_repair_of_one_folder_leaves_the_other_folders_as_they_are
    repair(dirs: [INTENT])

    assert_equal [true, true], [at("#{INTENT}/resources/references/plan.md"), at("#{OTHER}/plan.md")]
  end

  def test_a_held_folder_is_left_as_it_is
    before = intent_files
    repair(held: Set[INTENT])

    assert_equal [before, true], [intent_files, at("#{OTHER}/resources/references/plan.md")]
  end

  def test_the_old_lock_and_graph_md_go_with_their_rows
    write("#{INTENT}/graph.md", "# Graph\n")
    hold_rows("graph.md", "# Graph\n")
    repair

    assert_equal [false, false], [at("#{INTENT}/delivery.lock"), at("#{INTENT}/graph.md")]
    refute_includes row_paths("documents"), "graph.md"
  end

  def test_each_revision_entry_becomes_an_amended_line_with_its_own_time
    write("#{INTENT}/revisions.md", REVISIONS)
    repair
    reason = Plastic::Layout.amendment_reason(:revision)

    assert_equal [["2026-08-30T09:15:00Z", "revisions.md v1: The first change.; #{reason}"],
      ["2026-09-01T00:00:00Z", "revisions.md v2: The second.; #{reason}"]], amended
    refute at("#{INTENT}/revisions.md")
  end

  def test_an_unreadable_revisions_file_refuses_before_anything_changes
    write("#{INTENT}/revisions.md", "Some notes with no date.\n")
    before = files_without_databases

    assert_raises(Plastic::Refused) { repair }
    assert_equal before, files_without_databases
  end

  def test_a_closed_intent_gets_an_amended_line_for_each_move_and_removal
    close
    repair
    texts = amended.map(&:last)

    assert_includes texts, "moved plan.md to resources/references/plan.md; #{Plastic::Layout.amendment_reason(:move)}"
    assert_includes texts, "removed delivery.lock; #{Plastic::Layout.amendment_reason(:remove)}"
  end

  def test_an_open_intent_gets_no_amended_line_for_its_moves
    repair

    assert_empty amended
  end
end
