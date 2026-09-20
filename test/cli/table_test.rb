# encoding: UTF-8
# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../scripts/lib/cli"

class CliTableTest < Minitest::Test
  LIB = File.expand_path("../../scripts/lib", __dir__)

  def test_the_table_is_frozen
    assert_predicate Plastic::CLI::TABLE, :frozen?
  end

  def test_the_table_holds_every_command_batch_one_ships
    assert_equal %w[continue help install next rollback status uninstall update version],
      Plastic::CLI::TABLE.keys.sort
  end

  def test_every_row_names_a_file_a_class_and_a_summary
    Plastic::CLI::TABLE.each_value do |file, const, summary|
      assert_kind_of String, file
      assert_kind_of String, const
      refute_empty summary.to_s, "every command needs a one-line summary"
    end
  end

  def test_every_row_names_a_file_that_exists
    Plastic::CLI::TABLE.each do |name, (file, _const, _summary)|
      path = File.join(LIB, "cli", "#{file}.rb")

      assert_path_exists path, "#{name} names #{file}, which is not on disk"
    end
  end

  def test_every_row_loads_a_command_class
    Plastic::CLI::TABLE.each do |name, (file, const, _summary)|
      require File.join(LIB, "cli", "#{file}.rb")
      klass = Plastic::CLI::Commands.const_get(const)

      assert_operator klass, :<, Plastic::CLI::Command, "#{name} must be a Command"
    end
  end

  def test_every_command_class_carries_a_usage_line_that_starts_with_its_name
    Plastic::CLI::TABLE.each do |name, (file, const, _summary)|
      require File.join(LIB, "cli", "#{file}.rb")
      usage = Plastic::CLI::Commands.const_get(const)::USAGE_LINE

      assert usage.start_with?("plastic #{name}"), "#{name}'s usage line reads #{usage.inspect}"
    end
  end

  def test_no_summary_ends_with_a_full_stop
    Plastic::CLI::TABLE.each do |name, (_file, _const, summary)|
      refute summary.end_with?("."), "#{name}'s summary is a line, not a sentence"
    end
  end
end
