# frozen_string_literal: true

require_relative "../commands/installer_helper"
require_relative "../../../scripts/lib/plastic/workflows/check_installation"

class CheckInstallationTest < Plastic::TestCase
  include InstallerHelper

  def bin = File.join(@home, ".local", "bin")

  def check = run_workflow(Plastic::Workflows::CheckInstallation, harness: scoped_harness(env: { "PLASTIC_SHARE" => share, "PATH" => bin }))

  def make_whole
    activated("99.0.0-alpha.1")
    [File.join(share, "active", "runtime", "bundle", "bundler", "setup.rb"), File.join(bin, "plastic")].each do |file|
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, "")
      File.chmod(0o755, file)
    end
  end

  def test_with_no_release_only_ruby_is_checked
    outcome, context = check

    assert_equal :unmanaged, outcome
    assert_equal ["active:", "installation:", "ruby:"], printed_rows(context).map(&:first)
  end

  def test_a_release_with_no_bundle_names_the_repair_and_fails
    activated("99.0.0-alpha.1")

    outcome, context = check

    assert_includes printed_rows(context), ["repair:", Plastic::Workflows::InstallationHealth::INCOMPLETE]
    assert_equal "code_check_installation, gate: a part of the installation is broken; run the repairs named above, then check again",
      outcome.message
  end

  def test_a_whole_release_is_done
    make_whole

    assert_equal :done, check.first
  end
end
