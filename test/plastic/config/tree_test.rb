# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/config/tree"

class ConfigTreeTest < Plastic::TestCase
  def tree(text)
    path = File.join(@plastic_home, "config.yml")
    File.write(path, text)
    Plastic::Config::Tree.new(path)
  end

  def test_a_file_in_the_layout_is_read_as_written
    assert_includes tree("global: &shared\n  statusline: false\n").stream.to_yaml, "&shared"
  end

  def test_a_flat_file_is_read_as_the_sections_it_moves_to
    assert_equal({ "global" => { "statusline" => false } }, tree("statusline: false\n").stream.to_ruby.first)
  end
end
