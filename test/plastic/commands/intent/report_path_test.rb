# frozen_string_literal: true

require_relative "../../../test_helper"

class IntentReportPathTest < Plastic::TestCase
  include ConfigHomes

  FOLDER = "resources/output/reports"

  def call(path) = plastic("intent", "report", "1", path, table: Plastic::CLI::TABLE)

  def reported = store_database.rows("SELECT path FROM work_log WHERE kind = 'reported'").map(&:values)

  def documents = store_database.rows("SELECT path FROM documents").map { |row| row.fetch("path") }

  def dir = retrieval.intent("1").dir

  def setup
    super
    intent = open_intent
    write("#{intent.dir}/outcome.md", "# Outcome\n")
    write("#{intent.dir}/#{FOLDER}/page.html", "<p>page</p>\n")
    write("secret.txt", "a secret outside every intent\n")
    sync_up
  end

  def refused(path)
    result = call(path)
    [result.code, result.err.include?("Error"), reported, documents.include?(path)]
  end

  def test_a_path_outside_the_reports_folder_exits_1_and_writes_nothing
    write("#{dir}/resources/tmp/page.html", "<p>page</p>\n")

    assert_equal [1, false, [], false], refused("resources/tmp/page.html")
  end

  def test_a_path_that_climbs_out_with_dot_dot_exits_1_and_writes_nothing
    assert_equal [1, false, [], false], refused("#{FOLDER}/../../../../../secret.txt")
  end

  def test_a_dot_dot_that_stays_inside_the_folder_exits_1_too
    assert_equal [1, false, [], false], refused("#{FOLDER}/x/../page.html")
  end

  def test_an_absolute_path_exits_1_and_writes_nothing
    assert_equal [1, false, [], false], refused(File.join(store_root, dir, FOLDER, "page.html"))
  end

  def test_a_dot_part_exits_1_and_writes_nothing
    assert_equal [1, false, [], false], refused("#{FOLDER}/./page.html")
  end

  def test_an_empty_part_exits_1_and_writes_nothing
    assert_equal [1, false, [], false], refused("#{FOLDER}//page.html")
  end

  def test_the_problem_names_the_path_and_the_rule
    result = call("#{FOLDER}/../../secret.txt")

    assert_includes result.out + result.err, "#{FOLDER}/../../secret.txt holds a . or .. part"
  end

  def test_a_link_in_the_reports_folder_that_leads_outside_exits_1
    File.symlink(File.join(store_root, "secret.txt"), File.join(store_root, dir, FOLDER, "link.html"))

    assert_equal [1, false, [], false], refused("#{FOLDER}/link.html")
  end

  def test_a_type_the_sync_does_not_read_exits_1_and_writes_nothing
    write("#{dir}/#{FOLDER}/r.svg", "<svg><text>hi</text></svg>\n")
    result = call("#{FOLDER}/r.svg")

    assert_equal [1, []], [result.code, reported]
    assert_includes result.out + result.err, "the sync does not read .svg files"
  end

  def test_a_pdf_exits_1_and_does_not_crash
    write("#{dir}/#{FOLDER}/r.pdf", "%PDF-1.4\n\x00\x01binary\n")

    assert_equal [1, false, [], false], refused("#{FOLDER}/r.pdf")
  end

  def test_a_binary_file_of_a_read_type_exits_1_and_does_not_crash
    seed_config(@plastic_home, "global:\n  sync:\n    types: [md, html, pdf]\n")
    write("#{dir}/#{FOLDER}/r.pdf", "%PDF-1.4\n\x00\x01binary\n")
    result = call("#{FOLDER}/r.pdf")

    assert_equal [1, false, []], [result.code, result.err.include?("Error"), reported]
    assert_includes result.out + result.err, "not text"
  end
end
