# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/repair/run"
require_relative "../../../../test_helpers/resources_homes"

# The repair of one intent folder takes its core files and its scratch folder from the layout.
class RepairRunIntentTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  Resources = Plastic::Graph::Knowledge::Resources
  REPORT = "resources/output/reports/old.html"

  def folder = Plastic::Graph::Knowledge::StoreFolder.new(store_root)

  def repair = Plastic::Graph::Knowledge::Repair::Run.new(folder, store_graphs).call

  def amended = store_database.rows("SELECT path, text FROM work_log WHERE kind = 'amended'").map { |row| row.fetch("path") }

  def setup
    super
    write_old_layout
  end

  def test_a_report_that_nobody_asked_for_moves_into_the_tmp_folder_of_the_layout
    write("#{INTENT}/#{REPORT}", "<p>old</p>\n")
    repair

    assert_path_exists File.join(store_root, INTENT, Plastic::Layout.resource(:tmp), "old.html")
  end

  def test_a_link_rewritten_in_a_core_file_of_a_closed_intent_is_amended_for_that_file
    store_database.transaction { |batch| batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = '1'") }
    repair

    assert_equal [Plastic::Layout.name(:spec)], amended.uniq
  end
end
