# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseInstallTest < Minitest::Test
  include ReleaseHelper

  def test_verifies_stages_and_activates_a_release
    assert_equal "2.0.3", install(release_files)
    assert_equal "2.0.3", activation.active_version
    assert_equal ["releases", "active", "INSTALL.lock"].sort, Dir.children(install_home).sort
  end

  def test_installs_the_runtime_gems_before_the_switch
    seen = []
    bundle = ->(path) { seen << [path, activation.active_version] }
    install(release_files, bundle: bundle)

    assert_equal [[File.join(install_home, "releases", "2.0.3"), nil]], seen
  end

  def test_a_failed_gem_install_keeps_the_old_release_active
    install(release_files(version: "2.0.2"))
    error = assert_raises(InstallerRelease::ActivationError) do
      install(release_files, bundle: ->(_path) { raise "bundle failed" })
    end

    assert_equal ["bundle failed", "2.0.2"], [error.message, activation.active_version]
    assert_equal ["releases", "active", "INSTALL.lock"].sort, Dir.children(install_home).sort
  end

  def test_a_second_install_of_the_same_version_switches_to_it
    install(release_files(version: "2.0.2"))
    directory = release_files
    install(directory)
    activation.switch("2.0.2")

    assert_equal "2.0.3", install(directory)
    assert_equal %w[2.0.3 2.0.2], [activation.active_version, activation.previous_version]
  end

  def test_refuses_a_release_other_than_the_one_requested
    directory = release_files
    files = InstallerRelease::ReleaseFiles.new(directory)

    error = assert_raises(InstallerRelease::VerificationError) do
      installer.call(archive: files.archive, manifest: files.manifest, expected: InstallerRelease::Manifest.identity("2.0.4"))
    end
    assert_equal "release version does not match", error.message
    refute_path_exists install_home
  end

  private

  def activation = InstallerRelease::Activation.new(home: install_home)

  def installer(bundle: ->(_path) {}) = InstallerRelease::ReleaseInstall.new(home: install_home, bundle: bundle)

  def install(directory, bundle: ->(_path) {})
    files = InstallerRelease::ReleaseFiles.new(directory).verify
    version = files.manifest.dig("release", "version")
    installer(bundle: bundle).call(archive: files.archive, manifest: files.manifest, expected: InstallerRelease::Manifest.identity(version))
  end
end
