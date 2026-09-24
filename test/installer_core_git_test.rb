require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/install"

class InstallerCoreGitTest < Minitest::Test
  def setup
    @home = File.join(Dir.mktmpdir("installer-core"), "plastic")
    @install = Install.new(package_root: ".", plastic_home: @home, version: "x")
    @calls = []
  end

  def teardown
    FileUtils.rm_rf(File.dirname(@home))
  end

  def test_git_init_creates_the_home_and_initializes_it_quietly
    @install.git_init_if_absent(runner: ->(cmd) { @calls << cmd })

    assert File.directory?(@home)
    assert_equal [["git", "-C", @home, "init", "-q"]], @calls
  end

  def test_git_init_leaves_an_existing_repository_alone
    FileUtils.mkdir_p(File.join(@home, ".git"))

    @install.git_init_if_absent(runner: ->(cmd) { @calls << cmd })

    assert_empty @calls
  end
end
