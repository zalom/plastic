# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/installation_health"

class InstallationHealthTest < Plastic::TestCase
  include InstallerHelper

  def setup
    super
    activated("99.0.0-alpha.1")
  end

  def test_an_older_ruby_needs_a_repair
    assert_equal "install Ruby 4.0 or later", check("ruby:", ruby_version: "3.4.7").repair
  end

  def test_a_launcher_earlier_on_the_path_is_named
    other = FileUtils.mkdir_p(File.join(@home, "other")).first
    File.write(File.join(other, "plastic"), "")
    File.chmod(0o755, File.join(other, "plastic"))

    assert_match(/#{Regexp.escape(other)}.plastic runs first/, check("launcher:", path: other).value)
  end

  def test_a_running_installer_holds_the_lock
    File.open(File.join(share, "INSTALL.lock"), "a") do |lock|
      lock.flock(File::LOCK_EX)

      assert_equal "held by a running installer", check("installer lock:").value
    end
  end

  def test_a_settings_file_that_is_not_json_is_named
    settings = File.join(claude_folder, "settings.json")
    File.write(settings, "{ not json")

    assert_equal "#{settings} is not valid JSON", check("hooks:").value
  end

  def test_no_hooks_need_no_repair
    hooks = check("hooks:")

    assert_equal ["none registered", nil], [hooks.value, hooks.repair]
  end

  def check(label, ruby_version: "4.0.0", path: "")
    health = Plastic::Workflows::InstallationHealth.new(share: share, bin: File.join(@home, ".local", "bin"), path: path, home: @home, ruby_version: ruby_version)
    health.checks.find { |item| item.label == label }
  end
end
