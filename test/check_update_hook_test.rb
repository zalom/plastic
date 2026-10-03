require "minitest/autorun"
require "fileutils"
require "tmpdir"

# G5 (intent 391): hooks/check-update reads the GitHub releases list through curl,
# never npm. Source-text check (matrix row "check-update hook"): the script names curl
# and the releases URL, and never names npm.
class CheckUpdateHookTest < Minitest::Test
  SOURCE = File.read(File.expand_path("../hooks/check-update", __dir__))

  def test_names_curl
    assert_match(/curl/, SOURCE)
  end

  def test_names_the_github_releases_url
    assert_match(%r{https://api\.github\.com/repos/zalom/plastic/releases}, SOURCE)
  end

  def test_never_names_npm
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
    run_hook
    sleep 0.5

    refute_path_exists @calls
  end

  def test_a_cache_older_than_twelve_hours_checks_again
    File.utime(Time.now - (13 * 3600), Time.now - (13 * 3600), cache)
    run_hook

    assert wait_for(@calls), "the hook did not read the release list"
  end

  private

  def cache = File.join(@home, ".cache", "update-check.json")

  def run_hook
    env = { "PLASTIC_HOME" => @home, "PATH" => "#{File.join(@dir, "bin")}:#{ENV.fetch("PATH")}" }
    system(env, HOOK, out: File::NULL, err: File::NULL, exception: true)
  end

  def wait_for(path)
    50.times do
      return true if File.exist?(path)

      sleep 0.1
    end
    false
  end
end
