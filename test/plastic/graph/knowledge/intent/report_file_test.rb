# frozen_string_literal: true

require_relative "../../../../test_helper"
require "tmpdir"
require_relative "../../../../../lib/plastic/graph/knowledge/intent"
require_relative "../../../../../lib/plastic/graph/knowledge/intent/report_file"
require_relative "../../../../../lib/plastic/graph/knowledge/store_folder"
require_relative "../../../../../lib/plastic/graph/knowledge/sync_selection"

class ReportFileTest < Minitest::Test
  Intent = Struct.new(:intent_id, :dir)

  def report = Plastic::Graph::Knowledge::Intent::ReportFile.new(Intent.new("1", "store/1--x"), "resources/output/reports/a.html")

  def test_the_line_names_the_setting_in_parentheses
    assert_equal ["- #{report.path}", "- #{report.path} (mandatory)"], [report.line(""), report.line("mandatory")]
  end

  def test_an_outcome_that_lists_the_line_already_gives_nil
    assert_nil report.outcome("# Outcome\n\n## Reports\n\n- #{report.path}\n", "", "## Reports")
  end

  def test_an_outcome_that_does_not_list_the_report_gives_no_unlisted_outcome
    assert_nil report.unlisted("# Outcome\n\n## Reports\n\n- other.html\n", "## Reports")
  end

  def test_a_line_outside_the_section_stays_and_gives_no_unlisted_outcome
    assert_nil report.unlisted("# Outcome\n\n## Notes\n\n- #{report.path}\n", "## Reports")
  end

  def test_the_unlisted_outcome_takes_out_the_mandatory_form_too
    assert_equal "# Outcome\n", report.unlisted("# Outcome\n\n## Reports\n\n- #{report.path} (mandatory)\n", "## Reports")
  end

  def test_the_line_of_the_other_form_is_replaced
    body = "# Outcome\n\n## Reports\n\n- #{report.path}\n"

    assert_equal "# Outcome\n\n## Reports\n\n- #{report.path} (mandatory)\n", report.outcome(body, "mandatory", "## Reports")
  end

  def test_a_line_with_other_words_stays
    body = "# Outcome\n\n## Reports\n\n- #{report.path}, asked: \"x\"\n"

    assert_equal "#{body}- #{report.path}\n", report.outcome(body, "", "## Reports")
  end

  def problem(path, files = {}, type_read: true)
    Dir.mktmpdir do |root|
      files.each { |name, bytes| FileUtils.mkdir_p(File.dirname(File.join(root, name))).then { File.binwrite(File.join(root, name), bytes) } }
      selection = Struct.new(:read) { def reads_type?(_path) = read }.new(type_read)
      file = Plastic::Graph::Knowledge::Intent::ReportFile.new(Intent.new("1", "i"), path)
      file.problem(selection, Plastic::Graph::Knowledge::StoreFolder.new(root))
    end
  end

  def test_a_path_outside_the_reports_folder_is_a_problem
    refute_nil problem("outcome.md", { "i/outcome.md" => "x" })
  end

  def test_a_type_the_sync_does_not_read_is_a_problem
    assert_includes problem("resources/output/reports/a.html", { "i/resources/output/reports/a.html" => "x" }, type_read: false), "cannot be a report"
  end

  def test_a_missing_file_is_a_problem
    assert_equal "no file i/resources/output/reports/a.html", problem("resources/output/reports/a.html")
  end

  def test_a_binary_file_is_a_problem
    assert_includes problem("resources/output/reports/a.html", { "i/resources/output/reports/a.html" => "\x00\x01\x02binary" }), "is not text"
  end

  def test_a_link_that_leads_out_of_the_reports_folder_is_a_problem
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "i/resources/output/reports"))
      File.write(File.join(root, "secret.txt"), "secret\n")
      File.symlink(File.join(root, "secret.txt"), File.join(root, "i/resources/output/reports/link.html"))
      file = Plastic::Graph::Knowledge::Intent::ReportFile.new(Intent.new("1", "i"), "resources/output/reports/link.html")
      selection = Struct.new(:read) { def reads_type?(_path) = read }.new(true)

      assert_includes file.problem(selection, Plastic::Graph::Knowledge::StoreFolder.new(root)), "leads outside"
    end
  end

  def test_a_text_file_in_the_reports_folder_has_no_problem
    assert_nil problem("resources/output/reports/a.html", { "i/resources/output/reports/a.html" => "<p>x</p>\n" })
  end
end
