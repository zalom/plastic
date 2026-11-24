# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/graph/knowledge/outcome_delivery"

class KnowledgeOutcomeDeliveryLinesTest < Plastic::TestCase
  Lines = Struct.new(:lines) do
    def values(label) = lines.fetch(label, [])
  end

  RESUME = "resources/output/files/resume.pdf"

  def intent_folder = File.join(@home, "intent").tap { |dir| FileUtils.mkdir_p(File.join(dir, "resources/output/files")) }

  def delivery(lines, folder: intent_folder) = Plastic::Graph::Knowledge::OutcomeDelivery.new(Lines.new(lines), folder)

  def test_delivered_files_without_a_known_intent_folder_do_not_count
    refute_predicate delivery({ "Delivered" => ["#{RESUME} because x"] }, folder: nil), :recorded?
  end

  def test_delivered_files_in_the_intent_folder_count
    folder = intent_folder
    File.write(File.join(folder, RESUME), "%PDF")
    read = delivery({ "Delivered" => ["#{RESUME} because x"] }, folder:)

    assert_predicate read, :recorded?
  end

  def test_no_delivery_line_asks_for_one_of_the_three_lines
    read = delivery({})

    assert_equal [false, ""], [read.recorded?, read.finding]
    assert_includes read.message, "Committed: <branch> at <commit>"
  end

  def test_a_line_out_of_form_is_named_with_its_form_and_the_fix
    message = delivery({ "Merged" => ["no"] }).message

    assert_equal "outcome.md says 'Merged: no', which is not a delivery line in the form 'Merged: <branch> into <base> at <commit or pull request>'. " \
      "Fix that line or put the delivered files in place, then run plastic store sync up.", message
  end

  def test_a_delivered_path_that_is_not_there_is_named
    assert_equal "outcome.md says 'Delivered: #{RESUME} because x', but the intent folder holds no #{RESUME}. ",
      delivery({ "Delivered" => ["#{RESUME} because x"] }).finding
  end
end
