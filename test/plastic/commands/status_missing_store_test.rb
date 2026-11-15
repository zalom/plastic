# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/commands/status"

class StatusMissingStoreTest < Plastic::TestCase
  def test_a_home_with_no_global_store_and_no_project_named_says_the_global_store_has_no_folder
    empty_home = File.join(@home, "empty-plastic-home")
    FileUtils.mkdir_p(empty_home)

    result = plastic("status", env: { "PLASTIC_HOME" => empty_home }, table: Plastic::CLI::TABLE)

    assert_includes result.out, "global has no store folder"
  end
end
