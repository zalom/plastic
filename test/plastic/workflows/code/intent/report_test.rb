# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/intent/report"

# The step that records a report hands the work writer the ReportFile of the command.
class WorkflowReportTest < Minitest::Test
  Intent = Struct.new(:intent_id, :dir)
  Work = Struct.new(:given) { def report_intent(*args) = (self.given = args) && "uri" }
  Context = Struct.new(:work, :intent, :path, :settings, :reference) do
    def []=(_key, value)
      self.reference = value
    end
  end
  Mandatory = Struct.new(:names) { def mandatory?(path) = names.include?(path) }
  Settings = Struct.new(:selection)
  Selection = Struct.new(:reports)

  def test_the_step_passes_the_report_file_and_the_setting_text
    work = Work.new
    intent = Intent.new("1", "store/1--x")
    context = Context.new(work, intent, "resources/output/reports/a.html", Settings.new(Selection.new(Mandatory.new(%w[resources/output/reports/a.html]))))

    Plastic::Workflows::Code::Intent::Report.write(context)

    assert_equal [[Plastic::Graph::Knowledge::Intent::ReportFile.new(intent, "resources/output/reports/a.html"), "mandatory"], "uri"], [work.given, context.reference]
  end
end
