# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require_relative "../../support/child_process"
require "rbconfig"
require "tmpdir"
require_relative "../../varar/support/kernel_command"

# An uninstall started by the launcher runs on the Ruby and the kernel it
# removes: a release copied into a throwaway share, on a read-only Ruby
# folder of its own.
class UninstallRunningRubyTest < Minitest::Test
  REPO = File.expand_path("../../..", __dir__)

  def setup
    @home = Dir.mktmpdir("plastic-uninstall-ruby")
    FileUtils.mkdir_p(File.join(@home, ".claude"))
    KernelCommand.new(@home).run!("init", "1")
    copied_release
    FileUtils.chmod_R("a-w", ruby_folder)
  end

  def teardown
    FileUtils.chmod_R("u+w", @home)
    FileUtils.rm_rf(@home)
  end

  def test_removes_the_ruby_it_runs_on_and_still_prints_its_closing_lines
    out, err, status = ChildProcess.capture3(environment, launcher, "uninstall", "1", chdir: @home)

    assert_equal [0, "", false], [status.exitstatus, err, File.exist?(share)]
    assert_match(/removed:\s+#{Regexp.escape(share)}\n/, out)
    assert_match(/^next: plastic init$/, out)
  end

  private

  def share = File.join(@home, ".local", "share", "plastic")

  def launcher = File.join(@home, ".local", "bin", "plastic")

  def ruby_folder = File.join(share, "rubies", "4.0.7-jdx-2")

  def environment
    { "HOME" => @home, "PLASTIC_HOME" => File.join(@home, ".plastic"), "PLASTIC_TMP" => File.join(@home, "tmp") }
  end

  def release = File.join(share, "releases", "99.0.0")

  def active = File.join(share, "active")

  def ruby_program = File.join(ruby_folder, "bin", "ruby")

  def copy(source, target = release) = FileUtils.cp_r(File.join(REPO, source), target)

  def copied_kernel
    FileUtils.mkdir_p([File.join(release, "libexec"), File.dirname(launcher)])
    copy("scripts")
    copy("package.json")
    copy(File.join("bin", "plastic"), File.join(release, "libexec", "plastic"))
    File.write(File.join(release, "VERSION"), "99.0.0\n")
  end

  def copied_release
    copied_kernel
    script(ruby_program, "exec #{RbConfig.ruby} \"$@\"")
    script(File.join(release, "bin", "plastic"), "exec #{ruby_program} #{release}/libexec/plastic \"$@\"")
    File.symlink(release, active)
    File.symlink(File.join(active, "bin", "plastic"), launcher)
  end

  def script(path, line)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/sh\n#{line}\n")
    File.chmod(0o755, path)
  end
end
