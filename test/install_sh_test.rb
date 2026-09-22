# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class InstallShTest < Minitest::Test
  SCRIPT = File.expand_path("../install.sh", __dir__)

  def install(home, archive:)
    Open3.capture3({"HOME" => home, "PLASTIC_ARCHIVE_URL" => "file://#{archive}"}, "sh", SCRIPT)
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

  def test_a_download_that_fails_exits_one_and_links_nothing
    Dir.mktmpdir do |dir|
      _out, _err, status = install(dir, archive: File.join(dir, "missing.tgz"))

      assert_equal 1, status.exitstatus
      refute_path_exists File.join(dir, ".local", "bin", "plastic")
    end
  end
end

# The installer used to fetch releases/latest/download/plastic.tgz. That URL
# resolves to whichever release wears the Latest badge, and v2.0.0-alpha.27
# wore it with no assets at all, so a plain curl install 404'd. The installer
# now reads the release list and takes the newest release on the channel that
# actually carries the archive. A fake curl on the PATH serves both calls, so
# these tests never touch the network.
class InstallShChannelTest < Minitest::Test
  SCRIPT = File.expand_path("../install.sh", __dir__)

  RELEASES = <<~JSON
    [
      {"tag_name": "v2.0.0-alpha.29", "prerelease": true,
       "assets": [{"name": "plastic.tgz", "browser_download_url": "https://example.test/alpha29.tgz"}]},
      {"tag_name": "v2.0.0-alpha.27", "prerelease": false, "assets": []},
      {"tag_name": "v1.14.1", "prerelease": false,
       "assets": [{"name": "plastic.tgz", "browser_download_url": "https://example.test/stable.tgz"}]}
    ]
  JSON

  def setup
    @dir = Dir.mktmpdir("plastic-install-channel")
    @bindir = File.join(@dir, "fakebin")
    FileUtils.mkdir_p(@bindir)
    File.write(File.join(@dir, "releases.json"), RELEASES)
    write_fake_curl
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # Serves the API call from the fixture, records the download URL it is asked
  # for, and unpacks the real archive so the rest of the script proceeds.
  def write_fake_curl
    fake = File.join(@bindir, "curl")
    File.write(fake, <<~SH)
      #!/bin/sh
      url=""
      out=""
      while [ $# -gt 0 ]; do
        case "$1" in
          -o) out="$2"; shift 2 ;;
          -H) shift 2 ;;
          -*) shift ;;
          *) url="$1"; shift ;;
        esac
      done
      case "$url" in
        *api.github.com*) cat "#{File.join(@dir, "releases.json")}" ;;
        *) echo "$url" > "#{File.join(@dir, "asked-for")}"; cp "#{archive}" "$out" ;;
      esac
    SH
    File.chmod(0o755, fake)
  end

  def archive
    return @archive if @archive

    FileUtils.mkdir_p(File.join(@dir, "package", "bin"))
    File.write(File.join(@dir, "package", "bin", "plastic"), "#!/bin/sh\necho installed\n")
    File.chmod(0o755, File.join(@dir, "package", "bin", "plastic"))
    system("tar", "-czf", File.join(@dir, "plastic.tgz"), "-C", @dir, "package", exception: true)
    @archive = File.join(@dir, "plastic.tgz")
  end

  def install(channel: nil)
    home = File.join(@dir, "home")
    FileUtils.mkdir_p(home)
    env = {"HOME" => home, "PATH" => [@bindir, ENV.fetch("PATH", "")].join(File::PATH_SEPARATOR)}
    env["PLASTIC_CHANNEL"] = channel if channel
    Open3.capture3(env, "sh", SCRIPT)
  end

  def asked_for
    File.read(File.join(@dir, "asked-for")).strip
  end

  def test_the_default_channel_skips_a_prerelease_wearing_the_latest_badge
    _out, err, status = install

    assert_equal 0, status.exitstatus, err
    assert_equal "https://example.test/stable.tgz", asked_for
  end

  def test_the_alpha_channel_takes_the_newest_alpha_carrying_the_archive
    _out, err, status = install(channel: "alpha")

    assert_equal 0, status.exitstatus, err
    assert_equal "https://example.test/alpha29.tgz", asked_for
  end

  def test_a_channel_with_no_archive_exits_one_and_names_the_way_out
    File.write(File.join(@dir, "releases.json"), "[]")
    _out, err, status = install

    assert_equal 1, status.exitstatus
    assert_includes err, "PLASTIC_CHANNEL=alpha"
  end
end
