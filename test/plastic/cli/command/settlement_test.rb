# frozen_string_literal: true

require_relative "../../../test_helper"

class CommandSettlementTest < Plastic::TestCase
  Scope = Data.define(:named_slug, :projects)
  Workspace = Data.define(:scope)

  def settlement(json: false)
    @out = StringIO.new
    @err = StringIO.new
    klass = json ? Plastic::CLI::JsonOutput : Plastic::CLI::TextOutput
    output = klass.new(out: @out, err: @err)
    scope = Scope.new("alpha", { "main" => "/work/main" })
    Plastic::CLI::Command::Settlement.new(output, "plastic show ID", Workspace.new(scope))
  end

  def test_a_refusal_exits_three_and_prints_its_line
    assert_equal 3, settlement.settle(Plastic::Refused.new("no"))
    assert_includes @err.string, "no"
  end

  def test_a_failure_exits_one
    assert_equal 1, settlement.settle(Plastic::Failed.new("broke"))
  end

  def test_a_store_out_of_step_is_a_refusal_that_offers_the_update
    assert_equal 3, settlement.settle(Plastic::Graph::Behind.new("behind"))
    assert_includes @out.string, "plastic update"
  end

  def test_anything_else_prints_the_usage_and_exits_two
    assert_equal 2, settlement.settle(Plastic::Usage.new("missing ID"))
    assert_equal "plastic: missing ID\nplastic show ID\n", @err.string
  end

  def test_a_broken_projects_file_fails_after_the_rows
    assert_equal 1, settlement.broken(StandardError.new("bad file"))
    assert_includes @err.string, "bad file"
  end

  def test_a_broken_projects_file_in_json_prints_one_document
    assert_equal 1, settlement(json: true).broken(StandardError.new("bad file"))
    assert_includes @out.string + @err.string, "bad file"
  end
end
