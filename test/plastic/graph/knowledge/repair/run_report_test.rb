# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/repair/run"
require_relative "../../../../test_helpers/resources_homes"

class RepairRunReportTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  Resources = Plastic::Graph::Knowledge::Resources
  FOLDER = "resources/output/reports"
  PAGE = "<p><img src=\"page.svg\"> <a href=\"../../../reviews/r1.md\">review</a> <a href=\"https://example.com/\">web</a> <a href=\"../../../../2--beta/spec.md\">beta</a></p>\n"

  def folder = Plastic::Graph::Knowledge::StoreFolder.new(store_root)

  def repair(**options) = Plastic::Graph::Knowledge::Repair::Run.new(folder, store_graphs, **options).call

  def record(path, intent_id: "1", kind: "reported", position: 1)
    store_database.transaction do |batch|
      batch.put(:work_log, { intent_id:, position:, at: STAMP, phase: "", node: "", session_id: "s", kind:, path:, sha256: "", text: "the page" })
    end
  end

  def at(rel, dir: INTENT) = File.file?(File.join(store_root, dir, rel))

  def read(rel) = File.read(File.join(store_root, INTENT, rel))

  def setup
    super
    write_old_layout
    write("#{INTENT}/#{FOLDER}/page.html", PAGE)
    write("#{INTENT}/#{FOLDER}/page.svg", "<svg/>\n")
  end

  def test_a_recorded_report_keeps_the_files_it_links_to_and_its_bytes
    record("#{FOLDER}/page.html")
    repair

    assert_equal [true, true, PAGE], [at("#{FOLDER}/page.svg"), at("reviews/r1.md"), read("#{FOLDER}/page.html")]
  end

  def test_a_mandatory_report_keeps_the_files_it_links_to
    repair(reports: Plastic::Graph::Knowledge::Reports.new(mandatory: %w[page.html]))

    assert_equal [true, PAGE], [at("#{FOLDER}/page.svg"), read("#{FOLDER}/page.html")]
  end

  def test_the_files_of_a_removed_report_move_as_those_of_an_unasked_one
    record("#{FOLDER}/page.html")
    record("#{FOLDER}/page.html", kind: "removed", position: 2)
    repair

    assert_equal [false, true], [at("#{FOLDER}/page.svg"), at("resources/tmp/page.svg")]
  end

  def test_the_files_of_an_unasked_report_move_with_it
    repair

    assert_equal [false, true], [at("#{FOLDER}/page.svg"), at("resources/tmp/page.svg")]
  end

  def test_machine_files_in_the_reports_folder_stay
    write("#{INTENT}/#{FOLDER}/.DS_Store", "finder\n")
    repair

    assert at("#{FOLDER}/.DS_Store")
  end

  def test_a_lock_file_below_the_top_of_the_folder_is_an_ordinary_file
    write("#{INTENT}/#{FOLDER}/Gemfile.lock", "GEM\n")
    repair

    assert_equal [false, true], [at("#{FOLDER}/Gemfile.lock"), at("resources/tmp/Gemfile.lock")]
  end

  BETA = "store/2--beta"
  ACROSS = "<p><a href=\"../../../../2--beta/#{FOLDER}/old.html\">old</a></p>\n".freeze

  def across_intents
    write("#{INTENT}/#{FOLDER}/across.html", ACROSS)
    write("#{BETA}/#{FOLDER}/old.html", "<p>old</p>\n")
    write("#{BETA}/#{FOLDER}/loose.html", "<p>loose</p>\n")
    record("#{FOLDER}/across.html")
  end

  def test_a_recorded_report_keeps_a_file_of_another_intent_it_links_to_and_its_bytes
    across_intents
    repair

    assert_equal [true, ACROSS], [at("#{FOLDER}/old.html", dir: BETA), read("#{FOLDER}/across.html")]
  end

  def test_a_report_of_another_intent_that_no_listed_report_links_to_still_moves
    across_intents
    repair

    assert_equal [false, true], [at("#{FOLDER}/loose.html", dir: BETA), at("resources/tmp/loose.html", dir: BETA)]
  end

  def test_a_mandatory_report_keeps_a_file_of_another_intent_it_links_to
    write("#{INTENT}/#{FOLDER}/across.html", ACROSS)
    write("#{BETA}/#{FOLDER}/old.html", "<p>old</p>\n")
    repair(reports: Plastic::Graph::Knowledge::Reports.new(mandatory: %w[across.html]))

    assert at("#{FOLDER}/old.html", dir: BETA)
  end

  def test_the_intent_id_of_a_folder_with_a_second_double_dash_is_its_first_part
    write("store/7--two--parts/#{FOLDER}/old.html", "<p>old</p>\n")
    record("#{FOLDER}/old.html", intent_id: "7")
    repair

    assert at("#{FOLDER}/old.html", dir: "store/7--two--parts")
  end
end
