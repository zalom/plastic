# frozen_string_literal: true

require_relative "../../command_reference_helper"

class CommandReferenceDslMarkdownTest < Minitest::Test
  include CommandReferenceHelper

  def text = CommandReferenceHelper.files.fetch("docs/reference/dsl/README.md")

  def test_the_kernel_wide_endings_table_holds_exit_2_for_usage_and_links_the_settle_method
    table = text[/## How any call can end.*?(?=\n## |\z)/m]

    assert_match(/\| .*wrong argument.* \| 2 \|/, table)
    assert_includes table, "cli/command.rb"
  end

  def test_the_table_lists_each_kernel_wide_ending
    table = text[/## How any call can end.*?(?=\n## |\z)/m]

    ["--help", "missing store", "step that raises", "agent handoff"].each { |part| assert_includes table, part }
  end

  def test_the_dsl_page_wires_the_workflows_and_names_what_every_call_shares
    assert_includes text, "## Wire the workflows"
    assert_includes text, "(#wire-the-workflows)"
    assert_includes text, "workflows.svg"
    refute_includes text, "Wire the chain"

    shared = text[/## What every call shares.*?(?=\n---|\z)/m]

    ["lib/plastic/routine.rb#L", "lib/plastic/cli/command.rb#L", "lib/plastic/graph/database/connection_pool.rb#L"].each { |link| assert_includes shared, link }
  end

  def test_the_dsl_page_lists_the_shared_section_in_its_contents
    assert_includes text, "(#what-every-call-shares)"
  end

  def test_the_page_links_the_kernel_by_relative_path
    assert_includes text, "../../../lib/plastic/routine.rb"
  end
end
