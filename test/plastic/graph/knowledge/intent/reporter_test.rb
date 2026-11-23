# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/intent"
require_relative "../../../../../lib/plastic/graph/knowledge/intent/reporter"

class ReporterTest < Minitest::Test
  Intent = Struct.new(:intent_id, :dir)
  Document = Struct.new(:body)
  Retrieval = Struct.new(:body) { def fetch(_id, _file) = Document.new(body) }

  def restate(body, text)
    report = Plastic::Graph::Knowledge::Intent::ReportFile.new(Intent.new("1", "store/1--x"), "resources/output/reports/a.html")
    Plastic::Graph::Knowledge::Intent::Reporter.new({}, Retrieval.new(body), nil).restate(report, text)
  end

  def test_an_outcome_that_does_not_list_the_report_is_not_written
    refute restate("# Outcome\n", "mandatory")
  end

  def test_an_outcome_that_lists_the_right_line_is_not_written
    refute restate("# Outcome\n\n## Reports\n\n- resources/output/reports/a.html (mandatory)\n", "mandatory")
  end
end
