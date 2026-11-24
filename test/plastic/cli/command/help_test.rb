# frozen_string_literal: true

require_relative "../../../test_helper"

class CommandHelpTest < Plastic::TestCase
  class Declared
    extend Plastic::CLI::Declarations
  end

  def lines(&) = Plastic::CLI::Command::Help.new(Class.new(Declared, &), "plastic show ID").lines

  def test_with_nothing_declared_it_lists_the_switches_every_command_takes
    assert_equal ["plastic show ID", "        --json", "        --project SLUG"], lines
  end

  def test_each_argument_and_option_gets_its_own_line
    help = lines do
      argument :id, label: "ID", text: "the intent"
      option :dir, switch: "--dir DIR", text: "where"
    end

    assert_equal ["        ID                           the intent", "        --dir DIR                    where"], help[1, 2]
  end

  def test_a_long_description_prints_its_lines_after_the_usage_line
    help = lines { long_description "Opens the databases.", "No sandbox." }

    assert_equal ["plastic show ID", "        Opens the databases.", "        No sandbox."], help[0, 3]
  end
end
