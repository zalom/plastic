# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseManagedHomeTest < Minitest::Test
  include ReleaseHelper

  def user_home = File.join(@root, "home")

  def managed
    InstallerRelease::ManagedHome.new(plastic_home: install_home, user_home:, launcher: File.join(@root, "bin", "plastic"))
  end

  def touch(*parts)
    path = File.join(*parts)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "")
    path
  end

  def test_the_core_files_of_the_plastic_home_are_managed
    version = touch(install_home, "VERSION")

    assert_includes managed.paths, version
  end

  def test_stores_are_never_managed
    store = touch(install_home, "stores", "alpha", "store", "index.json")

    refute(managed.paths.any? { |path| store.start_with?(path) })
  end

  def test_plastic_agent_files_are_managed_and_other_agents_are_not
    ours = touch(user_home, ".claude", "agents", "plastic-executor.md")
    theirs = touch(user_home, ".claude", "agents", "reviewer.md")

    assert_equal [true, false], [managed.paths.include?(ours), managed.paths.include?(theirs)]
  end

  def test_the_launcher_is_always_managed
    assert_equal File.join(@root, "bin", "plastic"), managed.paths.last
  end
end
