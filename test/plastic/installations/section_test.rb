# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/installations"

class InstallationsSectionTest < Plastic::TestCase
  def section(file) = Plastic::Installations::Section.new(file:, opening: "<!-- BEGIN", closing: "<!-- END -->")

  def path = File.join(@home, "CLAUDE.md")

  def test_a_section_whose_file_is_gone_changes_nothing
    assert_nil section(path).strip
  end

  def test_a_file_without_the_section_stays_unchanged
    File.write(path, "# Mine\n")

    assert_equal [nil, "# Mine\n"], [section(path).strip, File.read(path)]
  end
end
