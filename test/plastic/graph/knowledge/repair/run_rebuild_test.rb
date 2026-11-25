# frozen_string_literal: true

require "delegate"
require "sqlite3"
require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/repair/run"
require_relative "../../../../test_helpers/resources_homes"

# A repair rebuilds the plan, the checklist and the action files of an old intent as records, then removes the files and moves their rows to legacy.db.
class RepairRunRebuildTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  CHECKLIST = "# Checklist\n\n- [x] ACTION_1 - first\n- [ ] ACTION_2 - second\n\n## Session Log\n| Date | Items Completed | Notes |\n|---|---|---|\n| 2026-07-02 | ACTION_1 | Done. |\n"
  BRIEF = "# ACTION 1 - First\n\nDo it.\n\n## Result\nIt works.\n"
  PLAN = "# Plan\n\n## Approach\nSmall steps.\n"

  def folder = Plastic::Graph::Knowledge::StoreFolder.new(store_root)

  def repair(**options) = Plastic::Graph::Knowledge::Repair::Run.new(folder, store_graphs, **options).call

  def close(status) = store_database.transaction { |batch| batch.write(:intents, "UPDATE intents SET status = :status WHERE intent_id = '1'", status:) }

  def path(rel) = File.join(store_root, INTENT, rel)

  def nodes = store_database.rows("SELECT id, title, state FROM nodes WHERE intent_id = '1' ORDER BY id").map(&:values)

  def legacy_paths = SQLite3::Database.new(File.join(store_root, "legacy.db")).execute("SELECT path FROM legacy_intents_data ORDER BY path").flatten

  # A work graph that cannot write the rebuilt records, as a locked database fails.
  class FailingWork < SimpleDelegator
    def rebuild_intents(_rebuilds) = raise(IOError, "locked")
  end

  # A rebuild whose log lines cannot be read, after its node and packet are written.
  class BrokenRebuild
    Draft = Data.define(:title, :state, :packet, :findings, :reason)

    def dir = "store/1--alpha"

    def intent_id = "1"

    def nodes = [Draft.new(title: "Step", state: "open", packet: "A brief.", findings: nil, reason: nil)]

    def lines = raise(IOError, "unreadable")
  end

  def setup
    super
    write_old_layout
    write("#{INTENT}/checklist.md", CHECKLIST)
    write("#{INTENT}/plan.md", PLAN)
    write("#{INTENT}/actions/ACTION_1.md", BRIEF)
    write("#{INTENT}/actions/.gitkeep", "")
  end

  def test_each_checklist_step_becomes_a_node_with_its_state
    close("done")
    repair

    assert_equal %w[done abandoned], nodes.map(&:last)
  end

  def test_a_brief_is_the_packet_of_its_node
    repair

    assert_equal BRIEF, File.read(path("resources/tmp/packets/#{nodes.first.first}.md"))
    assert_equal ["resources/tmp/packets/#{nodes.first.first}.md"], store_database.rows("SELECT path FROM node_inputs WHERE intent_id = '1'").map { |row| row.fetch("path") }
  end

  def test_a_session_log_row_is_a_dated_noted_line
    repair

    assert_equal ["2026-07-02T00:00:00Z"], store_database.rows("SELECT at FROM work_log WHERE kind = 'noted' AND text LIKE 'Session log of 2026-07-02%'").map { |row| row.fetch("at") }
  end

  def test_the_plan_approach_is_a_ruling
    repair

    assert_equal ["Approach: Small steps."], store_database.rows("SELECT text FROM rulings WHERE intent_id = '1' AND text LIKE 'Approach:%'").map { |row| row.fetch("text").sub(/\AD\d+: /, "") }
  end

  def test_the_rebuilt_files_and_the_empty_gitkeep_are_removed
    repair

    assert_equal [], %w[plan.md checklist.md actions/ACTION_1.md actions/.gitkeep actions].select { |rel| File.exist?(path(rel)) }
  end

  def keep_row(rel)
    store_database.transaction { |batch| batch.put(:legacy_intents_data, { intent_id: "1", path: rel, body: "old #{rel}", updated_at: STAMP }) }
  end

  def test_the_rows_of_the_files_go_to_legacy_db
    %w[plan.md checklist.md].each { |rel| keep_row(rel) }
    repair

    assert_equal [%w[checklist.md plan.md], []], [legacy_paths, store_database.rows("SELECT path FROM legacy_intents_data").map { |row| row.fetch("path") }]
  end

  def test_a_closed_intent_gets_an_amended_line_for_the_rebuild
    close("done")
    repair

    assert_equal 1, store_database.rows("SELECT 1 FROM work_log WHERE kind = 'amended' AND text LIKE '%rebuilt%'").size
  end

  def test_a_second_repair_adds_nothing
    repair
    before = [nodes, store_database.rows("SELECT * FROM work_log").size]
    repair

    assert_equal before, [nodes, store_database.rows("SELECT * FROM work_log").size]
  end

  def test_the_preview_names_the_rebuild_and_writes_nothing
    before = [files_without_databases, nodes]
    lines = Plastic::Graph::Knowledge::Repair::Plan.new(folder, states: {}).preview

    assert_match(/rebuild/, lines.to_s)
    assert_equal before, [files_without_databases, nodes]
  end

  def test_a_failed_write_leaves_files_and_rows_as_they_were
    before = [files_without_databases, nodes]
    graphs = store_graphs
    failing = graphs.with(work: FailingWork.new(graphs.work))

    assert_raises(IOError) { Plastic::Graph::Knowledge::Repair::Run.new(folder, failing).call }
    assert_equal before, [files_without_databases, nodes]
  end
  def test_a_rebuild_that_fails_after_its_packet_removes_the_packet_and_the_rows
    before = [files_without_databases, nodes]

    assert_raises(IOError) { store_graphs.work.rebuild_intents([BrokenRebuild.new]) }
    assert_equal before, [files_without_databases, nodes]
  end
end
