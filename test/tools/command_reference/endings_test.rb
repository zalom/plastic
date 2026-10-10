# frozen_string_literal: true

require_relative "../../command_reference_helper"
require_relative "../../fixtures/routines"

class CommandReferenceEndingsTest < Minitest::Test
  include CommandReferenceHelper

  ENDING_LINE = /\b(gate|outcome|next_step|raise|rescue|respond)\b|def settle|"decision"/

  def test_a_refusal_gate_ends_in_exit_3_on_the_line_of_its_gate
    gate = exit_rows("intent end", 3).find { |ending| ending.file.end_with?("workflows/prepare_ending.rb") }

    assert_equal :gate, gate.kind
    assert_match(/\bgate\b/, source_line(gate.file, gate.line))
  end

  def test_a_failure_gate_ends_in_exit_1
    assert(exit_rows("intent end", 1).any? { |ending| ending.kind == :gate })
  end

  def test_a_failure_handoff_ends_in_exit_1_and_a_plain_handoff_in_exit_0
    model = CommandReference::Model.new(CommandReferenceHelper::ROOT, table: Fixtures::TABLE)

    assert_equal [1], model.page("kernel review").endings.select { |ending| ending.kind == :handoff }.map(&:exit_code)
    assert_equal [0], model.page("kernel draft").endings.select { |ending| ending.kind == :handoff }.map(&:exit_code)
  end

  def test_a_no_chain_command_ends_on_its_next_step_lines
    rows = exit_rows("project list", 0)

    assert_equal ["plastic project new SLUG PATH", "plastic status"], rows.select { |ending| ending.kind == :next_step }.map(&:next_text)
  end

  def test_a_hook_has_only_exit_0
    assert_equal [0], page("hook end").endings.map(&:exit_code).uniq
  end

  def test_the_record_hook_shows_the_stop_gate_decision
    assert(page("hook record").endings.any? { |ending| ending.file.end_with?("hooks/stop_gate.rb") })
  end

  def test_a_computed_next_step_reads_decided_at_run_time_on_its_line
    row = page("status").endings.find { |ending| ending.kind == :next_step && ending.next_text == "decided at run time" }

    refute_nil row
    assert_match(/next_step/, source_line(row.file, row.line))
  end

  def test_a_module_call_raise_is_an_exit_2_row_on_the_module_file
    usage = exit_rows("backup restore", 2).select { |ending| ending.file.end_with?("commands/backup_store.rb") }

    refute_empty usage
    assert(usage.all? { |ending| source_line(ending.file, ending.line).include?("raise") })
  end

  def test_a_command_with_a_code_step_has_one_rescue_row_on_the_workflow_base
    rescued = page("intent end").endings.select { |ending| ending.kind == :rescue }

    assert_equal 1, rescued.size
    assert_equal "scripts/lib/plastic/code_workflow.rb", rescued.first.file
  end

  def test_a_gate_row_never_prints_the_word_none_after_next
    CommandReferenceHelper.pages.each_value { |page| page.endings.each { |ending| refute_match(/next: none/, ending.next_text) } }
  end

  def test_every_ending_line_holds_the_statement_that_decides_it
    CommandReferenceHelper.pages.each_value do |page|
      page.endings.each do |ending|
        assert_match ENDING_LINE, source_line(ending.file, ending.line), "#{page.words}: #{ending.kind} at #{ending.file}:#{ending.line}"
      end
    end
  end

  def raise_texts(words) = page(words).endings.select { |ending| ending.kind == :raise && ending.file.end_with?("backup_store.rb") }.map { |ending| source_line(ending.file, ending.line) }

  def test_a_backup_command_lists_only_the_raises_its_call_can_reach
    texts = raise_texts("backup list")

    refute_empty texts
    assert(texts.none? { |text| text.include?("give") || text.include?("error.message") })
  end

  def test_a_backup_command_with_a_check_call_lists_the_raises_that_check_reaches
    %w[backup\ restore backup\ purge].each do |words|
      texts = raise_texts(words)

      assert_includes texts.join("\n"), "give", words
      assert_includes texts.join("\n"), "error.message", words
    end
  end

  def test_the_own_check_call_of_a_backup_command_is_part_of_its_own_call
    check = page("backup restore").own_call.check

    assert_equal "scripts/lib/plastic/commands/backup_restore.rb", check.file
    assert_includes check.code.join("\n"), "one_of"
    assert_nil page("backup list").own_call.check
  end
end
