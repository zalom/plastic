# frozen_string_literal: true

require_relative "../../../command_reference_helper"

class CommandReferenceMarkdownIndexTest < Minitest::Test
  include CommandReferenceHelper

  def text = CommandReference::Markdown::Index.new(CommandReferenceHelper.pages.values).to_s

  def test_there_are_thirteen_groups
    assert_equal 13, text.scan(/^## /).size
    assert_includes text, "## Core"
  end

  def test_every_table_command_is_linked_once
    Plastic::CLI::TABLE.each_key do |words|
      assert_equal 1, text.scan("(#{words.tr(" ", "-")}/README.md)").size, words
    end
  end

  def test_the_core_group_holds_the_distribution_and_entry_commands
    core = text[/## Core.*?(?=\n## )/m]

    %w[install update rollback uninstall version doctor status next search auto].each { |word| assert_includes core, "`plastic #{word}`" }
  end

  def test_backup_alone_is_in_the_backup_family
    assert_includes text[/## backup.*?(?=\n## )/m], "`plastic backup`"
  end
end
