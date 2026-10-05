# frozen_string_literal: true

require "open3"
require_relative "release_helper"

class InstallerReleaseInstallTest < Minitest::Test
  include ReleaseHelper

  def test_verifies_stages_and_activates_a_release
    assert_equal "2.0.3", install(release_files)
    assert_equal "2.0.3", activation.active_version
    assert_equal ["releases", "active", "INSTALL.lock"].sort, Dir.children(install_home).sort
  end

  def test_installs_the_runtime_gems_with_the_chosen_ruby_before_the_switch
    seen = []
    bundle = ->(path, ruby) { seen << [path, ruby.path, activation.active_version] }
    install(release_files, bundle: bundle)

    assert_equal [[File.join(install_home, "releases", "2.0.3"), RbConfig.ruby, nil]], seen
  end

  def test_the_launcher_starts_the_chosen_ruby_by_its_full_path
    install(release_files)
    launcher = File.read(File.join(release_path("2.0.3"), "bin", "plastic"))

    assert_includes launcher, "exec #{RbConfig.ruby} --disable-gems -rrbconfig #{File.join(release_path("2.0.3"), "libexec", "plastic")} \"$@\""
  end

  def test_the_launcher_runs_with_an_empty_path
    install(release_files)
    out, status = Open3.capture2e({ "HOME" => @root, "PATH" => "" }, File.join(release_path("2.0.3"), "bin", "plastic"))

    assert_equal ["2.0.3\n", true], [out, status.success?]
  end

  def test_an_update_to_another_ruby_keeps_the_ruby_of_the_older_release
    install(release_files(version: "2.0.2"), ruby: RbConfig.ruby)
    install(release_files, ruby: newer_ruby)

    assert_includes File.read(File.join(release_path("2.0.2"), "bin", "plastic")), "exec #{RbConfig.ruby} "
    assert_includes File.read(File.join(release_path("2.0.3"), "bin", "plastic")), "exec #{newer_ruby} "
  end

  def test_a_failed_gem_install_keeps_the_old_release_active
    install(release_files(version: "2.0.2"))
    error = assert_raises(InstallerRelease::ActivationError) do
      install(release_files, bundle: ->(_path, _ruby) { raise "bundle failed" })
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

  def release_path(version) = File.join(install_home, "releases", version)

  def newer_ruby
    path = File.join(@root, "newer", "bin", "ruby")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/sh\nexec #{RbConfig.ruby} \"$@\"\n")
    File.chmod(0o755, path)
    path
  end

  def installer(bundle: ->(_path, _ruby) {}, ruby: RbConfig.ruby)
    InstallerRelease::ReleaseInstall.new(home: install_home, bundle: bundle, choice: ->(_manifest) { InstallerRelease::Ruby.new(ruby) })
  end

  def install(directory, bundle: ->(_path, _ruby) {}, ruby: RbConfig.ruby)
    files = InstallerRelease::ReleaseFiles.new(directory).verify
    version = files.manifest.dig("release", "version")
    installer(bundle: bundle, ruby: ruby)
      .call(archive: files.archive, manifest: files.manifest, expected: InstallerRelease::Manifest.identity(version))
  end
end
