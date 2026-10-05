require "minitest/autorun"
require "fileutils"
require "open3"
require "rbconfig"
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

# The Ruby the release of a home runs on, as its launcher starts it.
def active_ruby(home)
  ruby = File.join(home, ".local", "share", "plastic", "active", "bin", "ruby")
  FileUtils.mkdir_p(File.dirname(ruby))
  File.write(ruby, "#!/bin/sh\nexec #{RbConfig.ruby} \"$@\"\n")
  File.chmod(0o755, ruby)
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
    active_ruby(@dir)
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
    env = { "HOME" => @dir, "PLASTIC_HOME" => @home, "PATH" => "#{File.join(@dir, "bin")}:#{ENV.fetch("PATH")}" }
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

# With no Ruby on PATH, the update check runs on the Ruby of the active
# release. The cache is a named pipe, so the test reads the hook's one
# write as it lands.
class CheckUpdateRubyTest < Minitest::Test
  HOOK = File.expand_path("../hooks/check-update", __dir__)
  TOOLS = %w[dirname mkdir cat grep find date env].freeze

  def setup
    @dir = Dir.mktmpdir("plastic-check-update-ruby")
    FileUtils.mkdir_p([File.join(plastic_home, ".cache"), bin])
    File.write(File.join(plastic_home, "VERSION"), "2.0.3\n")
    TOOLS.each { |tool| File.symlink(tool_path(tool), File.join(bin, tool)) }
    File.write(File.join(bin, "curl"), %(#!/bin/sh\nprintf '%s' '[{"tag_name":"v2.0.4","draft":false}]'\n))
    File.chmod(0o755, File.join(bin, "curl"))
    active_ruby(@dir)
    File.mkfifo(cache)
    File.utime(Time.now - (13 * 3600), Time.now - (13 * 3600), cache)
  end

  def teardown = FileUtils.rm_rf(@dir)

  def test_runs_the_selector_on_the_ruby_of_the_active_release
    out, err, status = Open3.capture3({ "HOME" => @dir, "PLASTIC_HOME" => plastic_home, "PATH" => bin }, HOOK)

    assert_equal [0, "", ""], [status.exitstatus, out, err]
    assert_includes written, '"latest":"2.0.4"'
  end

  private

  def plastic_home = File.join(@dir, ".plastic")

  def bin = File.join(@dir, "bin")

  def cache = File.join(plastic_home, ".cache", "update-check.json")

  def tool_path(tool) = ENV.fetch("PATH").split(":").map { |dir| File.join(dir, tool) }.find { |path| File.executable?(path) }

  def written
    File.open(cache, File::RDWR | File::NONBLOCK) do |pipe|
      IO.select([pipe], nil, nil, 10) ? pipe.readpartial(4096) : ""
    end
  end
end
