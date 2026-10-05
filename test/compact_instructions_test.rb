# frozen_string_literal: true

require_relative "test_helper"
require "compact_instructions"

class CompactInstructionsTest < Plastic::TestCase
  def test_the_body_imports_the_installed_plastic_page
    assert_includes CompactInstructions::BODY.lines.map(&:chomp), "@~/.plastic/PLASTIC.md"
  end

  def test_the_body_hash_is_the_first_twelve_characters_of_its_digest
    assert_equal Digest::SHA256.hexdigest(CompactInstructions::BODY)[0, 12], CompactInstructions.body_hash
  end
end
