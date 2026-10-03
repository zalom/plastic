# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require "tmpdir"
require_relative "../scripts/lib/installer_core"

class InstallerKernelHooksTest < Minitest::Test
  def install(settings, times: 1)
    Dir.mktmpdir do |home|
      path = File.join(home, "settings.json")
      File.write(path, JSON.generate(settings))
      installer = InstallerCore.new(package_root: Dir.pwd, plastic_home: File.join(home, ".plastic"))
      times.times { capture_io { installer.send(:merge_claude_hooks, path) } }
      yield JSON.parse(File.read(path)), home
    end
  end

  def rebind(home, package_root, hooks)
    FileUtils.mkdir_p(package_root)
    File.write(File.join(package_root, "VERSION"), "2.0.3\n")
    path = File.join(home, "settings.json")
    File.write(path, JSON.generate("hooks" => hooks))
    installer = InstallerCore.new(package_root: package_root, plastic_home: File.join(home, ".plastic"))
    capture_io { installer.send(:merge_claude_hooks, path) }
    JSON.parse(File.read(path))
  end

  def read_json(*parts) = JSON.parse(File.read(File.join(*parts)))

  def commands(settings, event) = Array(settings["hooks"][event]).flat_map { |group| group["hooks"].map { |hook| hook["command"] } }

  def test_the_install_writes_the_kernel_hooks
    install({}) do |settings, home|
      kernel = %("#{File.join(home, ".plastic", "bin", "plastic")}")
      expected = { "SessionStart" => "#{kernel} hook resume --harness claude-code",
                   "Stop" => "#{kernel} hook record --harness claude-code", "SessionEnd" => "#{kernel} hook record --end" }

      assert_empty(expected.reject { |event, text| commands(settings, event).any? { |cmd| cmd.include?(text) } })
    end
  end

  def test_the_install_keeps_check_update
    install({}) { |settings, _home| assert(commands(settings, "SessionStart").any? { |cmd| cmd.end_with?("plastic-check-update") }) }
  end

  def test_a_release_install_binds_the_hooks_to_the_active_launcher
    Dir.mktmpdir do |home|
      share = File.join(home, ".local", "share", "plastic")
      former = %(env -u RUBYOPT "#{File.join(home, ".plastic", "bin", "plastic")}" hook resume --harness claude-code || true)
      settings = rebind(home, File.join(share, "releases", "2.0.3"), "SessionStart" => [{ "matcher" => "", "hooks" => [{ "type" => "command", "command" => former }] }])

      resume = commands(settings, "SessionStart").grep(/hook resume/)

      assert_equal [%(env -u RUBYOPT "#{File.join(share, "active", "bin", "plastic")}" hook resume --harness claude-code || true)], resume
    end
  end

  def test_the_ledger_and_the_manifest_carry_local_time_with_its_offset
    Dir.mktmpdir do |home|
      installer = InstallerCore.new(package_root: Dir.pwd, plastic_home: File.join(home, ".plastic"))
      installer.send(:ledger_append, "2.0.3", "install")
      installer.send(:write_manifest, [], File.join(home, "manifest.json"))

      times = [read_json(home, ".plastic", "versions.json")["at"], read_json(home, "manifest.json")["created"]]

      assert_empty(times.grep_v(/[+-]\d\d:\d\d\z/))
    end
  end

  def test_a_second_install_keeps_one_group_per_event
    install({}, times: 2) do |settings, _home|
      assert_equal 1, commands(settings, "Stop").size
    end
  end
end
