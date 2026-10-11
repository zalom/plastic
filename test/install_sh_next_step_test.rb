# frozen_string_literal: true

require_relative "support/install_sh_helper"

class InstallShNextStepTest < Minitest::Test
  include InstallShHelper

  def test_a_local_release_claims_no_trust_and_names_the_next_command
    out, = install_local("2.0.3")

    assert_includes out, "claims no release trust"
    assert_includes out, "next: plastic init"
  end

  def test_an_installed_home_names_the_version_check_as_the_next_command
    FileUtils.mkdir_p(File.join(@home, ".plastic"))
    File.write(File.join(@home, ".plastic", "VERSION"), "2.0.2\n")
    out, = install_local("2.0.3")

    assert_includes out, "next: plastic version"
    refute_includes out, "next: plastic init"
  end

  def test_prints_a_path_hint_and_edits_no_profile
    out, = install_local("2.0.3")

    assert_includes out, "is not on your PATH"
    assert_empty Dir.children(@home) - [".local"]
  end
end
