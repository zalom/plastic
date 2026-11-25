# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/compact_instructions"

class CompactInstructionsTest < Plastic::TestCase
  def test_the_body_imports_the_installed_plastic_page
    assert_includes Plastic::Installations::CompactInstructions::BODY.lines.map(&:chomp), "@~/.plastic/PLASTIC.md"
  end
end
