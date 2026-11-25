# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseLaunchCheckTest < Minitest::Test
  include ReleaseHelper

  def test_accepts_a_release_whose_launcher_reports_its_version
    assert InstallerRelease::LaunchCheck.new.call(package("2.0.3", fake_launcher("2.0.3")), "2.0.3")
  end

  def test_refuses_a_launcher_that_reports_another_version
    error = refusal(package("2.0.3", fake_launcher("2.0.3", reported: "2.0.2")))

    assert_equal "the launcher of 2.0.3 reports 2.0.2", error.message
  end

  def test_refuses_a_launcher_that_cannot_start
    error = refusal(package("2.0.3", "#!/bin/sh\necho 'cannot load such file' >&2\nexit 1\n"))

    assert_equal "the launcher of 2.0.3 does not start: cannot load such file", error.message
  end

  def test_refuses_a_launcher_that_prints_no_version
    error = refusal(package("2.0.3", "#!/bin/sh\necho '{\"result\":{}}'\n"))

    assert_equal "the launcher of 2.0.3 reports no version", error.message
  end

  def test_starts_the_launcher_without_the_callers_bundle
    runs = []
    check = InstallerRelease::LaunchCheck.new(run: ->(env, command) { runs << [env, command] && ['{"result":{"version":"2.0.3"}}', "", true] })
    check.call(File.join(@root, "release"), "2.0.3")

    expected = %w[RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_SETUP BUNDLER_VERSION].to_h { |name| [name, nil] }

    assert_equal [[expected, [File.join(@root, "release", "bin", "plastic"), "version", "--json"]]], runs
  end

  private

  def package(version, launcher)
    path = File.join(@root, "release-#{version}")
    write_package(path, version, launcher)
    path
  end

  def refusal(path) = assert_raises(InstallerRelease::VerificationError) { InstallerRelease::LaunchCheck.new.call(path, "2.0.3") }
end
