# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseActivationLaunchTest < Minitest::Test
  include ReleaseHelper

  def test_a_release_that_reports_another_version_never_becomes_active
    installer = activation_with("2.0.2")
    candidate = staged_candidate("2.0.3")
    File.write(File.join(candidate, "bin", "plastic"), fake_launcher("2.0.3", reported: "2.0.2"))

    error = assert_raises(InstallerRelease::ActivationError) { installer.activate(candidate, version: "2.0.3") }
    assert_equal ["the launcher of 2.0.3 reports 2.0.2", ["2.0.2", nil], %w[2.0.2]], [error.message, versions(installer), installer.releases.versions]
    assert_path_exists candidate
  end

  def test_a_first_release_that_cannot_start_leaves_no_pointers
    installer = InstallerRelease::Activation.new(home: install_home)
    candidate = staged_candidate("2.0.3")
    File.write(File.join(candidate, "bin", "plastic"), "#!/bin/sh\nexit 1\n")

    assert_raises(InstallerRelease::ActivationError) { installer.activate(candidate, version: "2.0.3") }
    assert_equal [[nil, nil], []], [versions(installer), installer.releases.versions]
  end

  def test_refuses_a_rollback_to_a_release_that_cannot_start
    installer = activation_with("2.0.2", "2.0.3")
    File.write(File.join(installer.releases.path("2.0.2"), "bin", "plastic"), "#!/bin/sh\nexit 1\n")

    assert_raises(InstallerRelease::ActivationError) { installer.switch(installer.previous_version) }
    assert_equal %w[2.0.3 2.0.2], versions(installer)
  end
end
