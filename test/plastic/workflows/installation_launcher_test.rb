# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/installation_health"

class InstallationLauncherTest < Plastic::TestCase
  def bin = File.join(@home, "bin")

  def launcher(directory)
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, "plastic"), "")
    File.chmod(0o755, File.join(directory, "plastic"))
  end

  def check(*path) = Plastic::Workflows::InstallationLauncher.new(bin:, path: path.join(File::PATH_SEPARATOR)).check

  def test_the_linked_launcher_first_on_path_needs_no_repair
    launcher(bin)

    assert_equal ["launcher:", File.join(bin, "plastic"), nil], check(bin).to_h.values
  end

  def test_another_launcher_first_on_path_is_named_with_the_repair
    launcher(other = File.join(@home, "other"))
    launcher(bin)

    result = check(other, bin)

    assert_equal "#{File.join(other, "plastic")} runs first, not #{File.join(bin, "plastic")}", result.value
    assert_equal "put #{bin} first on PATH; the installer links the launcher there", result.repair
  end

  def test_no_launcher_on_path_is_reported
    assert_equal "not on PATH", check(bin).value
  end
end
