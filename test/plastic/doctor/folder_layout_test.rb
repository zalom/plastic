# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../test_helpers/resources_homes"
require_relative "../../../lib/plastic/doctor"
require_relative "../../../lib/plastic/doctor/folder_layout"

# The doctor check names each intent folder of a store that breaks the layout, says what is wrong there, and names the
# repair; it reads the folder and writes nothing.
class DoctorFolderLayoutTest < Plastic::TestCase
  include ResourcesHomes

  Scope = Struct.new(:plastic_home, :projects)
  REPAIR = "plastic intent repair --all --project global"
  LABEL = "layout global 1--alpha:"
  REVISIONS = "# Revisions\n\n## Revision v1 - 2026-08-30\n\nThe first change.\n"

  def checks = Plastic::Doctor::FolderLayout.checks(Scope.new(@plastic_home, {}))

  def folder = Plastic::Graph::Knowledge::StoreFolder.new(File.join(@plastic_home, "stores", "global"))

  def put(files) = files.each { |rel, text| folder.write("#{INTENT}/#{rel}", text) }

  def test_names_a_folder_that_breaks_the_layout_what_is_wrong_and_the_repair
    put(OLD_FILES)
    outside = MOVES.keys.sort.join(", ")

    assert_equal [[LABEL, "outside the layout: #{outside}; retired: delivery.lock", REPAIR]], checks.map(&:to_a)
  end

  def test_a_store_whose_folders_follow_the_layout_is_no_finding
    put("spec.md" => "# Spec\n")

    assert_equal [["layout global:", "ok, every intent folder follows the layout", nil]], checks.map(&:to_a)
  end

  def test_each_broken_folder_gets_its_own_row
    put("plan.md" => "# Plan\n")
    folder.write("store/2--beta/revisions.md", REVISIONS)

    assert_equal [[LABEL, "outside the layout: plan.md", REPAIR], ["layout global 2--beta:", "revisions.md holds entries that belong in the work log", REPAIR]],
      checks.map(&:to_a)
  end

  def test_a_conflict_is_a_finding_that_names_the_target
    put("reviews/r1.md" => "a\n", "resources/tmp/reviews/r1.md" => "b\n")
    found = checks.first

    assert_includes found.value, "resources/tmp/reviews/r1.md"
    assert_equal REPAIR, found.repair
  end

  def test_an_unreadable_revisions_md_names_the_file_and_a_repair_by_hand
    put("spec.md" => "# Spec\n", "revisions.md" => "no entries here\n")
    found = checks.first

    assert_includes found.value, "#{INTENT}/revisions.md holds no revision entry the repair can read"
    assert_equal "fix #{INTENT}/revisions.md by hand, then run plastic doctor again", found.repair
  end

  def test_the_retired_entries_of_the_store_folder_name_the_repair
    put("spec.md" => "# Spec\n")
    folder.write("store/.sessions/a.json", "{}\n")
    folder.write("store/work_graph.db", "")

    assert_equal [["layout global store/:", "retired: store/.sessions/, store/work_graph.db", REPAIR]], checks.map(&:to_a)
  end

  def test_an_entry_that_holds_data_is_left_to_a_person
    put("spec.md" => "# Spec\n")
    folder.write("store/work_graph.db", "rows\n")

    assert_equal [["layout global store/work_graph.db:", "it holds data, and the layout does not allow it here",
      "move store/work_graph.db out of the store folder by hand, then run plastic doctor again"]], checks.map(&:to_a)
  end

  def root(files) = files.each { |rel, text| File.write(File.join(folder.root, rel), text) }

  def test_an_entry_of_the_store_root_the_layout_does_not_name_is_left_to_a_person
    put("spec.md" => "# Spec\n")
    root("REVIEWS.md" => "# Reviews\n")

    assert_equal [["layout global REVIEWS.md:", "the layout does not name it", "move REVIEWS.md out of the store by hand, then run plastic doctor again"]],
      checks.map(&:to_a)
  end

  def test_the_entries_the_layout_allows_or_names_at_the_store_root_are_no_finding
    put("spec.md" => "# Spec\n")
    root(".gitignore" => "*.db\n", "knowledge_graph.db-wal" => "", "project.yml" => "slug: global\n", "AGENTS.md" => "# Agents\n", ".DS_Store" => "")
    FileUtils.mkdir_p(File.join(folder.root, "originals"))

    assert_equal [["layout global:", "ok, every intent folder follows the layout", nil]], checks.map(&:to_a)
  end

  # A store whose database the pool never opened, so the damaged file is what the check reads.
  def test_a_store_database_that_cannot_be_read_leaves_the_reports_folder_unjudged
    beta = Plastic::Graph::Knowledge::StoreFolder.new(File.join(@plastic_home, "stores", "beta"))
    { "store/1--alpha/spec.md" => "# Spec\n", "store/1--alpha/resources/output/reports/page.html" => "<p>page</p>\n",
      Plastic::Graph::Schema.file(:knowledge) => "not a database\n" }.each { |rel, text| beta.write(rel, text) }
    found = Plastic::Doctor::FolderLayout.checks(Scope.new(@plastic_home, { "beta" => {} }), reports: Plastic::Graph::Knowledge::Reports.new(mandatory: []))

    assert_equal ["layout global:", "layout beta:"], found.map(&:label)
  end

  def test_the_check_changes_no_file
    put(OLD_FILES)
    before = snapshot(@plastic_home)
    checks

    assert_equal before, snapshot(@plastic_home)
  end
end

# With the reports of the store, the check names exactly the reports a repair would move.
class DoctorFolderLayoutReportsTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  Scope = Struct.new(:plastic_home, :projects)
  Reports = Plastic::Graph::Knowledge::Reports
  FOLDER = "resources/output/reports"

  def checks(mandatory: []) = Plastic::Doctor::FolderLayout.checks(Scope.new(@plastic_home, {}), reports: Reports.new(mandatory:))

  def alpha(mandatory: []) = checks(mandatory:).find { |check| check.label == "layout global 1--alpha:" }

  def setup
    super
    write("#{INTENT}/spec.md", "# Spec\n")
    write("#{INTENT}/#{FOLDER}/page.html", "<p>page</p>\n")
  end

  def record(path, kind: "reported", position: 1)
    store_database.transaction do |batch|
      batch.put(:work_log, { intent_id: "1", position:, at: STAMP, phase: "", node: "", session_id: "s", kind:, path:, sha256: "", text: "the page" })
    end
  end

  def test_a_done_intent_that_lacks_a_required_file_is_listed_with_no_repair
    store_database.transaction { |batch| batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = '1'") }
    row = checks.find { |check| check.label == "layout global 1--alpha:" && check.repair.nil? }

    assert_includes row.value, "done, and lacks outcome.md"
  end

  def test_a_report_no_line_records_is_outside_the_layout
    assert_equal "outside the layout: #{FOLDER}/page.html", alpha.value
  end

  def test_a_recorded_report_is_in_the_layout
    record("#{FOLDER}/page.html")

    assert_nil alpha
  end

  def test_a_removed_report_is_outside_the_layout_again
    record("#{FOLDER}/page.html")
    record("#{FOLDER}/page.html", kind: "removed", position: 2)

    assert_equal "outside the layout: #{FOLDER}/page.html", alpha.value
  end

  def test_a_report_the_setting_names_is_in_the_layout
    assert_nil alpha(mandatory: ["page.html"])
  end
end
