# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/cli/rule_files"
require_relative "../../../lib/plastic/doctor"

class CLIRuleFilesTest < Plastic::TestCase
  def agents_path = File.join(@home, "AGENTS.md")

  def test_the_agents_file_written_to_an_empty_folder_names_plastic_md_for_the_doctor
    Plastic::CLI::RuleFiles.new(@home, "blog").write_absent

    assert_nil Plastic::Doctor::InstructionLine.new(agents_path, Plastic::Doctor::Core::PLASTIC_LINE).problem
  end
end
