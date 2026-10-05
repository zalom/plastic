# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/routine"

class RoutinePreviewOutputTest < Minitest::Test
  RecordedOutput = Struct.new(:rows, :steps) do
    def row(label, value) = rows << [label, value]

    def next_step(command, because:) = steps << [command, because]
  end

  Copy = Struct.new(:unused) do
    def original(text) = text
  end

  def setup
    @recorded = RecordedOutput.new([], [])
    @output = Plastic::Routine::PreviewOutput.new(@recorded, Copy.new, "plastic graph show 1")
  end

  def test_a_wrote_row_reads_as_would_write
    @output.row("wrote:", "1 intent")

    assert_equal [["would write:", "1 intent"]], @recorded.rows
  end

  def test_any_other_row_passes_through_unchanged
    @output.row("node:", "n1")

    assert_equal [["node:", "n1"]], @recorded.rows
  end

  def test_the_next_step_is_the_original_command_with_the_preview_reason
    @output.next_step("plastic graph show 1 --dry-run", because: "ignored")

    assert_equal [["plastic graph show 1", Plastic::Routine::PreviewOutput::BECAUSE]], @recorded.steps
  end
end
