# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class InstallShTest < Minitest::Test
  SCRIPT = File.expand_path("../install.sh", __dir__)

  def install(home, *arguments, archive: nil)
    env = {"HOME" => home, "PLASTIC_ARCHIVE_URL" => archive && "file://#{archive}"}
    Open3.capture3(env, "sh", SCRIPT, *arguments)
  end

  def archive_in(dir)
    FileUtils.mkdir_p(File.join(dir, "package", "bin"))
    File.write(File.join(dir, "package", "bin", "plastic"), "#!/bin/sh\necho installed\n")
    File.chmod(0o755, File.join(dir, "package", "bin", "plastic"))
    system("tar", "-czf", File.join(dir, "plastic.tgz"), "-C", dir, "package", exception: true)
    File.join(dir, "plastic.tgz")
  end

  def test_the_linked_command_runs_from_the_unpacked_archive
    Dir.mktmpdir do |dir|
      install(dir, archive: archive_in(dir))
      out, = Open3.capture2(File.join(dir, ".local", "bin", "plastic"))

      assert_equal "installed\n", out
    end
  end

  def test_the_next_step_is_plastic_install
    Dir.mktmpdir do |dir|
      out, = install(dir, archive: archive_in(dir))

      assert_includes out, "next: plastic install"
    end
  end

  def test_an_unknown_channel_exits_two
    Dir.mktmpdir do |dir|
      _out, _err, status = install(dir, "nightly")

      assert_equal 2, status.exitstatus
    end
  end
end
