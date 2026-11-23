# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/intent"
require_relative "../../../../../lib/plastic/graph/knowledge/intent/reporter"

class ReporterTest < Minitest::Test
  Intent = Struct.new(:intent_id, :dir)
  Document = Struct.new(:body)
  Retrieval = Struct.new(:body) { def fetch(_id, _file) = Document.new(body) }

  class Writing < Plastic::Graph::Knowledge::Intent::Reporter
    attr_reader :written

    def writer = (@written = []
                  self)

    def write(*args) = @written << args
  end

  def restate(body, text, reporter: Plastic::Graph::Knowledge::Intent::Reporter, retrieval: Retrieval.new(body))
    report = Plastic::Graph::Knowledge::Intent::ReportFile.new(Intent.new("1", "store/1--x"), "resources/output/reports/a.html")
    reporter.new({}, retrieval, nil).restate(report, text)
  end

  def test_an_outcome_that_does_not_list_the_report_is_not_written
    refute restate("# Outcome\n", "mandatory")
  end

  def test_an_outcome_that_lists_the_right_line_is_not_written
    refute restate("# Outcome\n\n## Reports\n\n- resources/output/reports/a.html (mandatory)\n", "mandatory")
  end

  def test_a_line_in_the_other_form_is_written_to_the_outcome_alone
    reporter = Writing.new({}, Retrieval.new("# Outcome\n\n## Reports\n\n- resources/output/reports/a.html\n"), nil)
    report = Plastic::Graph::Knowledge::Intent::ReportFile.new(Intent.new("1", "store/1--x"), "resources/output/reports/a.html")

    assert_equal [true, [["1", "outcome.md", "# Outcome\n\n## Reports\n\n- resources/output/reports/a.html (mandatory)\n"]]],
      [reporter.restate(report, "mandatory"), reporter.written]
  end

  def test_an_intent_with_no_outcome_file_is_not_written
    refute restate(nil, "mandatory", retrieval: Struct.new(:none) { def fetch(*) = nil }.new)
  end

  def test_the_reporter_takes_a_report_file_and_has_no_intent_and_path_wrappers
    reporter = Plastic::Graph::Knowledge::Intent::Reporter

    assert_equal [true, false, false], [reporter.public_method_defined?(:record), reporter.public_method_defined?(:write), reporter.public_method_defined?(:body)]
  end
end
