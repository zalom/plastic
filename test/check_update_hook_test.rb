require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"

# G5 (intent 391): hooks/check-update reads the GitHub releases list through curl,
# never npm. Source-text check (matrix row "check-update hook"): the script names curl
# and the releases URL, and never names npm.
class CheckUpdateHookTest < Minitest::Test
  SOURCE = File.read(File.expand_path("../hooks/check-update", __dir__))

  def test_the_hook_reads_releases_through_curl
    assert_match(/curl/, SOURCE)
  end

  def test_names_the_github_releases_url
    assert_match(%r{https://api\.github\.com/repos/zalom/plastic/releases}, SOURCE)
  end

  def test_the_hook_never_names_npm_anywhere
    refute_match(/npm/, SOURCE)
  end
end

# The update notice reads the release list at most once every 12 hours. A
# fake curl on PATH records each call, so the test reaches no network.
class CheckUpdateThrottleTest < Minitest::Test
  HOOK = File.expand_path("../hooks/check-update", __dir__)

  def setup
    @dir = Dir.mktmpdir("plastic-check-update")
    @home = File.join(@dir, ".plastic")
    @calls = File.join(@dir, "curl-calls")
    FileUtils.mkdir_p([File.join(@home, ".cache"), File.join(@dir, "bin")])
    File.write(File.join(@home, "VERSION"), "2.0.3\n")
    curl = File.join(@dir, "bin", "curl")
    File.write(curl, "#!/bin/sh\necho call >> \"#{@calls}\"\n")
    File.chmod(0o755, curl)
    File.write(cache, "{}\n")
  end

  def teardown = FileUtils.rm_rf(@dir)

  def test_a_cache_younger_than_twelve_hours_skips_the_check
    assert_equal ["", "", 0], run_hook

    refute_path_exists @calls
  end

  def test_a_cache_older_than_twelve_hours_checks_again
    File.utime(Time.at(0), Time.at(0), cache)

    assert_equal ["", "", 0], run_hook
    assert_path_exists @calls, "the hook did not read the release list"
  end

  private

  def cache = File.join(@home, ".cache", "update-check.json")

  def run_hook
    env = { "PLASTIC_HOME" => @home, "PLASTIC_UPDATE_CHECK_WAIT" => "1", "PATH" => "#{File.join(@dir, "bin")}:#{ENV.fetch("PATH")}" }
    out, err, status = Open3.capture3(env, HOOK)
    [out, err, status.exitstatus]
  end
end
