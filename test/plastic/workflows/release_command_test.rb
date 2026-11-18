# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/scope"
require_relative "../../../lib/plastic/workflows/release_command"

class ReleaseCommandTest < Minitest::Test
  def command(env = {}) = Plastic::Workflows::ReleaseCommand.of(Plastic::Scope.new(env:, home: "/h", directory: "/h"))

  def test_the_install_line_runs_the_active_releases_script_with_the_default_folders
    line = command.install("1.0.0", "2.0.0")

    assert_includes line, "/h/.local/share/plastic/releases/1.0.0/scripts/install-release --directory /h/.local/share/plastic/download --version 2.0.0"
    assert_includes line, "--home /h/.local/share/plastic --bin /h/.local/bin --plastic-home /h/.plastic --user-home /h"
  end

  def test_the_switch_line_names_the_version_and_honours_the_share_and_bin_settings
    line = command("PLASTIC_SHARE" => "/s", "PLASTIC_BIN" => "/b").switch("1.0.0", "0.9.0")

    assert_includes line, "/s/releases/1.0.0/scripts/install-release --switch 0.9.0 --home /s --bin /b"
  end
end
