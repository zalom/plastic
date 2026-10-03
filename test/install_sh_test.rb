# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "fileutils"
require "open3"
require "tmpdir"
require_relative "../scripts/lib/installer_release"

# Runs install.sh against throwaway homes. Releases are built in a temp
# directory with the repository's own installer code inside the archive. A
# fake curl serves the release list and the release files, and a fake
# sha256sum written in Ruby checks the sums, so no test reaches the network
# or depends on the machine's digest tools.
module InstallShHelper
  REPO = File.expand_path("..", __dir__)
  SCRIPT = File.join(REPO, "install.sh")
  INSTALLER_FILES = ["scripts/install-release", "scripts/lib/installer_release.rb", "scripts/lib/installer_release"].freeze

  def setup
    @dir = Dir.mktmpdir("plastic-install-sh")
    @home = File.join(@dir, "home")
    @fakebin = File.join(@dir, "fakebin")
    FileUtils.mkdir_p([@home, @fakebin])
    write_tool("sha256sum", FAKE_SHA256SUM)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  FAKE_SHA256SUM = <<~RUBY
    #!/usr/bin/env ruby
    require "digest"
    ok = File.readlines(ARGV.fetch(1)).all? do |line|
      sum, name = line.split
      File.file?(name) && Digest::SHA256.file(name).hexdigest == sum
    end
    exit(ok ? 0 : 1)
  RUBY

  def write_tool(name, body)
    path = File.join(@fakebin, name)
    File.write(path, body)
    File.chmod(0o755, path)
  end

  def share = File.join(@home, ".local", "share", "plastic")

  def launcher = File.join(@home, ".local", "bin", "plastic")

  def release(version)
    directory = File.join(@dir, "releases", "v#{version}")
    return directory if Dir.exist?(directory)

    write_package(File.join(directory, "package"), version)
    archive = File.join(directory, "plastic.tgz")
    system("tar", "-czf", archive, "-C", directory, "package", exception: true)
    identity = InstallerRelease::Manifest.identity(version).merge("platform" => "universal", "architecture" => "universal")
    InstallerRelease::Manifest.write(File.join(directory, "plastic.manifest.json"), archive: archive, release: identity)
    File.write(File.join(directory, "plastic.tgz.sha256"), "#{Digest::SHA256.file(archive).hexdigest}  plastic.tgz\n")
    directory
  end

  def write_package(package, version)
    INSTALLER_FILES.each do |path|
      FileUtils.mkdir_p(File.dirname(File.join(package, path)))
      FileUtils.cp_r(File.join(REPO, path), File.join(package, path))
    end
    FileUtils.mkdir_p(File.join(package, "bin"))
    File.write(File.join(package, "VERSION"), "#{version}\n")
    File.write(File.join(package, "bin", "plastic"), "#!/bin/sh\necho #{version}\n")
    File.chmod(0o755, File.join(package, "bin", "plastic"))
  end

  def environment(extra = {})
    { "HOME" => @home, "PATH" => [@fakebin, ENV.fetch("PATH")].join(File::PATH_SEPARATOR) }.merge(extra)
  end

  def install(*arguments, **extra)
    Open3.capture3(environment(extra.transform_keys(&:to_s)), "sh", SCRIPT, *arguments)
  end

  def install_local(version, *arguments, **extra) = install(*arguments, PLASTIC_LOCAL_RELEASE: release(version), **extra)

  def run_launcher = Open3.capture2(launcher).first
end

class InstallShLocalTest < Minitest::Test
  include InstallShHelper

  def test_installs_a_local_release_and_links_the_launcher
    out, err, status = install_local("2.0.3")

    assert_equal 0, status.exitstatus, err
    assert_equal "2.0.3\n", run_launcher
    assert_includes out, "claims no release trust"
    assert_includes out, "next: plastic install"
    assert_equal "2.0.3", InstallerRelease::Activation.new(home: share).active_version
  end

  def test_a_second_install_of_the_same_release_succeeds
    install_local("2.0.3")
    _out, err, status = install_local("2.0.3")

    assert_equal 0, status.exitstatus, err
    assert_equal "2.0.3\n", run_launcher
  end

  def test_prints_a_path_hint_and_edits_no_profile
    out, = install_local("2.0.3")

    assert_includes out, "is not on your PATH"
    assert_empty Dir.children(@home) - [".local"]
  end

  def test_a_failed_checksum_leaves_the_installed_release_untouched
    install_local("2.0.2")
    File.binwrite(File.join(release("2.0.3"), "plastic.tgz"), "corrupt")
    _out, err, status = install_local("2.0.3")

    assert_equal 1, status.exitstatus
    assert_includes err, "checksum"
    assert_equal "2.0.2\n", run_launcher
    assert_equal ["2.0.2"], InstallerRelease::Activation.new(home: share).versions
  end

  def test_refuses_a_release_other_than_the_requested_version
    _out, err, status = install_local("2.0.3", PLASTIC_VERSION: "2.0.4")

    assert_equal 1, status.exitstatus
    assert_includes err, "v2.0.4"
    refute_path_exists share
  end

  def test_rejects_an_override_url
    _out, err, status = install(PLASTIC_ARCHIVE_URL: "https://example.test/plastic.tgz")

    assert_equal 1, status.exitstatus
    assert_includes err, "PLASTIC_LOCAL_RELEASE"
  end

  def test_a_dry_run_reads_the_release_and_changes_nothing
    out, err, status = install_local("2.0.3", "--dry-run")

    assert_equal 0, status.exitstatus, err
    assert_includes out, "would install Plastic 2.0.3"
    refute_path_exists File.join(@home, ".local")
  end

  def test_refuses_an_unknown_channel
    _out, err, status = install(PLASTIC_CHANNEL: "nightly")

    assert_equal 1, status.exitstatus
    assert_includes err, "stable, beta or alpha"
  end
end

class InstallShChannelTest < Minitest::Test
  include InstallShHelper

  ASSETS = '[{"name": "plastic.tgz"}, {"name": "plastic.tgz.sha256"}, {"name": "plastic.manifest.json"}]'

  def setup
    super
    write_releases(<<~JSON)
      [
        {"tag_name": "v2.1.0-alpha.29", "prerelease": true, "assets": #{ASSETS}},
        {"tag_name": "v2.1.0-alpha.27", "prerelease": false, "assets": []},
        {"tag_name": "v2.0.3", "prerelease": false, "assets": #{ASSETS}}
      ]
    JSON
    write_tool("curl", fake_curl)
  end

  def write_releases(json) = File.write(File.join(@dir, "releases.json"), json)

  def fake_curl
    <<~SH
      #!/bin/sh
      url=""
      out=""
      while [ $# -gt 0 ]; do
        case "$1" in
          -o) out="$2"; shift 2 ;;
          -H|--proto|--tlsv1.2) [ "$1" = "--tlsv1.2" ] && shift || shift 2 ;;
          -*) shift ;;
          *) url="$1"; shift ;;
        esac
      done
      case "$url" in
        *api.github.com*) cat "#{@dir}/releases.json" ;;
        *) echo "$url" >> "#{@dir}/asked-for"
           tag=$(basename "$(dirname "$url")")
           cp "#{@dir}/releases/$tag/$(basename "$url")" "$out" ;;
      esac
    SH
  end

  def asked_for = File.readlines(File.join(@dir, "asked-for"), chomp: true)

  def test_the_default_channel_takes_the_newest_stable_release
    release("2.0.3")
    _out, err, status = install

    assert_equal 0, status.exitstatus, err
    assert_includes asked_for, "https://github.com/zalom/plastic/releases/download/v2.0.3/plastic.tgz"
    assert_equal "2.0.3\n", run_launcher
  end

  def test_the_alpha_channel_takes_the_newest_alpha_with_all_three_files
    release("2.1.0-alpha.29")
    _out, err, status = install(PLASTIC_CHANNEL: "alpha")

    assert_equal 0, status.exitstatus, err
    assert_equal "2.1.0-alpha.29\n", run_launcher
  end

  def test_an_exact_version_skips_the_release_list
    release("2.0.2")
    _out, err, status = install(PLASTIC_VERSION: "2.0.2")

    assert_equal 0, status.exitstatus, err
    assert_equal "2.0.2\n", run_launcher
  end

  def test_a_dry_run_downloads_only_the_manifest
    release("2.0.3")
    _out, err, status = install("--dry-run")

    assert_equal 0, status.exitstatus, err
    assert_equal ["https://github.com/zalom/plastic/releases/download/v2.0.3/plastic.manifest.json"], asked_for
    refute_path_exists File.join(@home, ".local")
  end

  def test_a_channel_with_no_complete_release_names_the_way_out
    write_releases("[]")
    _out, err, status = install

    assert_equal 1, status.exitstatus
    assert_includes err, "PLASTIC_CHANNEL=alpha"
  end
end

class InstallShDependencyTest < Minitest::Test
  include InstallShHelper

  BASE_TOOLS = %w[mktemp rm mkdir ln cat cp uname dirname basename].freeze

  def test_names_each_missing_tool_with_both_platforms
    path = minimal_path(%w[ruby tar])
    _out, err, status = Open3.capture3({ "HOME" => @home, "PATH" => path }, "/bin/sh", SCRIPT)

    assert_equal 1, status.exitstatus
    assert_includes err, "needs curl"
    assert_includes err, "needs sha256sum or shasum"
    assert_includes err, "macOS:"
    assert_includes err, "Linux:"
  end

  def test_names_a_ruby_older_than_four
    write_tool("ruby", "#!/bin/sh\necho 3.3.5\n")
    _out, err, status = install

    assert_equal 1, status.exitstatus
    assert_includes err, "Ruby 4.0 or later"
    assert_includes err, "found Ruby 3.3.5"
  end

  private

  def minimal_path(tools)
    minbin = File.join(@dir, "minbin")
    FileUtils.mkdir_p(minbin)
    (BASE_TOOLS + tools).each { |tool| File.symlink(which(tool), File.join(minbin, tool)) }
    minbin
  end

  def which(tool)
    ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, tool) }.find { |path| File.executable?(path) }
  end
end
