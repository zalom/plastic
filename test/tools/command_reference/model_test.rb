# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceModelTest < Minitest::Test
  include CommandReferenceHelper

  STEP_LINE = /\b(gate|read|step|forget_stop)\b/

  def rows_of(page) = page.flows.flat_map { |flow| flow.rows }

  def test_every_table_row_yields_one_page
    assert_equal Plastic::CLI::TABLE.size, CommandReferenceHelper.pages.size
    assert_equal Plastic::CLI::TABLE.keys.sort, CommandReferenceHelper.pages.values.map(&:words).sort
  end

  def test_a_routine_chain_lists_its_workflows_in_order
    assert_equal %i[code_prepare_ending agent_finish_intent agent_check_merge code_close_intent agent_wind_down_intent], page("intent end").flows.map(&:key)
    assert_equal :routine, page("intent end").kind
  end

  def test_a_routine_with_its_own_call_keeps_the_code_before_the_chain
    own = page("update").own_call

    assert_equal "scripts/lib/plastic/commands/update.rb", own.file
    assert_includes own.code.join("\n"), "raise CLI::Command::Usage"
    assert_nil page("intent end").own_call
  end

  def test_a_command_from_an_included_module_shows_the_module_call
    own = page("backup list").own_call

    assert_equal "scripts/lib/plastic/commands/backup_store.rb", own.file
    assert_includes own.code.first, "def call"
  end

  def test_a_command_with_no_chain_gets_one_box_for_its_call
    project = page("project list")

    assert_equal :command, project.kind
    assert_empty project.flows
    assert_includes project.own_call.code.join("\n"), "scope.projects"
  end

  def test_a_hook_gets_one_box_for_respond_and_is_found_under_hooks
    hook = page("hook end")

    assert_equal :hook, hook.kind
    assert_equal "scripts/lib/plastic/hooks/end.rb", hook.file
    assert_includes hook.own_call.code.first, "def respond"
  end

  def test_every_row_and_outcome_links_a_line_that_holds_its_statement
    CommandReferenceHelper.pages.each_value do |page|
      rows_of(page).each do |row|
        refute_nil row.line, "#{page.words}: #{row.name}"
        assert_match STEP_LINE, source_line(row.file, row.line), "#{page.words}: #{row.name} at #{row.file}:#{row.line}"
      end
    end
  end

  def test_every_outcome_links_its_outcome_line_or_the_workflow
    CommandReferenceHelper.pages.each_value do |page|
      page.flows.flat_map(&:outcomes).each do |outcome|
        assert_match(/\boutcome\b/, source_line(outcome.file, outcome.line), "#{page.words}: #{outcome.name}")
      end
    end
  end

  def test_shared_and_class_method_steps_link_the_file_that_holds_them
    claim = page("node claim").flows.flat_map(&:rows).select { |row| row.kind == :gate }
    sync = page("sync up").flows.flat_map(&:rows).select { |row| row.kind == :gate }

    refute_empty claim
    assert_equal ["scripts/lib/plastic/workflows/sync_steps.rb"], sync.map(&:file).uniq
    assert(claim.all? { |row| source_line(row.file, row.line).match?(/\bgate\b/) })
  end

  def test_the_auto_page_builds_and_links_a_method_check_to_its_definition
    row = page("auto").flows.flat_map(&:rows).find { |found| found.check.to_s.include?("delivery_started?") }

    refute_nil row
    assert_match(/step/, source_line(row.file, row.line))
  end

  def test_a_forgotten_stop_links_the_workflow_base_file
    row = CommandReferenceHelper.pages.values.flat_map { |page| rows_of(page) }.find { |found| found.name == "forget a stop of an earlier call" }

    assert_equal "scripts/lib/plastic/code_workflow.rb", row.file
    assert_match(/def forget_stop/, source_line(row.file, row.line))
  end

  def test_every_row_line_exists_in_the_rows_own_file
    CommandReferenceHelper.pages.each_value do |page|
      rows_of(page).each do |row|
        total = File.readlines(File.join(CommandReferenceHelper::ROOT, row.file)).size
        assert_operator row.line, :<=, total, "#{page.words}: #{row.name}"
      end
    end
  end

  def test_the_model_takes_a_class_as_well_as_a_table_key
    model = CommandReference::Model.new(CommandReferenceHelper::ROOT)

    assert_equal model.page("version").words, model.page(Plastic::Commands::Version).words
  end
end
