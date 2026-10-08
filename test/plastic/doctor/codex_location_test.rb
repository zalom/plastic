# frozen_string_literal: true

require_relative "whole_home"
require_relative "../../../scripts/lib/plastic/doctor/codex_location"

class DoctorCodexLocationTest < Plastic::TestCase
  include WholeHome

  def check(env = {}) = Plastic::Doctor::CodexLocation.new(scope(env)).check

  def test_an_unset_codex_home_uses_the_installer_location
    assert_nil check.repair
  end

  def test_an_explicit_default_codex_home_passes
    assert_nil check("CODEX_HOME" => File.join(@home, ".codex")).repair
  end

  def test_another_codex_home_names_the_configuration_edit
    assert_includes check("CODEX_HOME" => File.join(@home, "custom")).repair, "unset CODEX_HOME"
  end
end
