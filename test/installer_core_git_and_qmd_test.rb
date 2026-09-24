require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/install"

class InstallerCoreGitAndQmdTest < Minitest::Test
  def setup
    @home = File.join(Dir.mktmpdir("installer-core"), "plastic")
    @install = Install.new(package_root: ".", plastic_home: @home, version: "x")
    @calls = []
  end

  def teardown
    FileUtils.rm_rf(File.dirname(@home))
  end

  def test_register_with_qmd_adds_the_global_store
    FileUtils.mkdir_p(File.join(@home, "store"))
    runner = ->(args) {
      @calls << args
      ["", true]
    }

    @install.register_with_qmd(runner: runner, detector: -> { true })

    assert_includes @calls, ["collection", "add", File.expand_path(File.join(@home, "store")), "--name", "plastic-global"]
  end

  def test_register_with_qmd_makes_no_call_when_qmd_is_absent
    @install.register_with_qmd(runner: ->(args) { @calls << args }, detector: -> { false })

    assert_empty @calls
  end
end
