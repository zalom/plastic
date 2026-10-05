# frozen_string_literal: true

require "digest"
require_relative "support/install_sh_helper"

# install.sh with no Ruby on PATH: it picks the pinned Ruby for the platform,
# checks it and puts it under the share. The tests run a copy of install.sh
# whose pins name a small Ruby that starts the test's own Ruby, served by a
# fake curl. Fake uname, sysctl and ldd programs stand in for each platform.
class InstallShRubyTest < Minitest::Test
  include InstallShHelper

  TOOLS = %w[mktemp rm mkdir ln cat cp dirname basename tar gzip grep wc tr cut sort chmod mv].freeze
  PLATFORMS = %w[arm64-darwin x86_64-darwin x86_64-linux aarch64-linux].freeze

  def setup
    super
    write_tool("curl", fake_curl)
    write_tool("ldd", "#!/bin/sh\necho 'ldd (GNU libc) 2.39'\n")
    on("Linux", "x86_64")
  end

  def test_installs_the_pinned_ruby_and_a_launcher_that_needs_no_path
    _out, err, status = install_with(ruby_archive)

    assert_equal 0, status.exitstatus, err
    assert_equal ["#{@sha}\n", "2.0.3\n"], [File.read(File.join(ruby_folder, ".plastic-ruby")), launch_with_empty_path]
    assert_includes File.read(File.join(share, "active", "bin", "plastic")), File.join(ruby_folder, "bin", "ruby")
  end

  def test_takes_the_linux_build_on_linux
    install_with(ruby_archive)

    assert_equal ["https://ruby.test/x86_64-linux.tar.gz"], asked_for
  end

  def test_takes_the_apple_silicon_build_in_a_rosetta_shell
    on("Darwin", "x86_64")
    write_tool("sysctl", "#!/bin/sh\necho 1\n")
    install_with(ruby_archive)

    assert_equal ["https://ruby.test/arm64-darwin.tar.gz"], asked_for
  end

  def test_takes_the_homebrew_build_with_its_token_on_an_intel_mac
    on("Darwin", "x86_64")
    write_tool("sysctl", "#!/bin/sh\necho 0\n")
    _out, err, status = install_with(ruby_archive)

    assert_equal 0, status.exitstatus, err
    assert_equal ["#{ghcr_url} Authorization: Bearer QQ=="], asked_for
  end

  def test_stops_on_a_musl_system
    write_tool("ldd", "#!/bin/sh\necho 'musl libc (x86_64)' >&2\nexit 1\n")
    _out, err, status = install_with(ruby_archive)

    assert_equal 1, status.exitstatus
    assert_includes err, "Alpine and other musl systems are not supported"
    assert_includes err, "glibc 2.29"
    refute_path_exists share
  end

  def test_stops_on_a_platform_without_a_build
    on("FreeBSD", "amd64")
    _out, err, status = install_with(ruby_archive)

    assert_equal 1, status.exitstatus
    assert_includes err, "no Ruby build exists for FreeBSD amd64"
    assert_includes err, "WSL"
  end

  def test_a_wrong_size_leaves_no_ruby
    _out, err, status = install_with(ruby_archive, size: File.size(ruby_archive) + 1)

    assert_equal 1, status.exitstatus
    assert_includes err, "not the pinned"
    refute_path_exists File.join(share, "rubies")
  end

  def test_a_wrong_fingerprint_leaves_no_ruby
    _out, err, status = install_with(ruby_archive, sha: "0" * 64)

    assert_equal 1, status.exitstatus
    assert_includes err, "does not match its pinned SHA-256"
    refute_path_exists File.join(share, "rubies")
  end

  def test_an_archive_with_a_link_leaves_no_ruby
    _out, err, status = install_with(archive_of("linked") { |bin| File.symlink("/bin/sh", File.join(bin, "ruby")) })

    assert_equal 1, status.exitstatus
    assert_includes err, "the Ruby archive holds an unsafe entry"
    refute_path_exists File.join(share, "rubies")
  end

  def test_a_ruby_that_does_not_start_leaves_no_ruby_folder
    _out, err, status = install_with(archive_of("broken") { |bin| executable(File.join(bin, "ruby"), "#!/bin/sh\necho broken\n") })

    assert_equal 1, status.exitstatus
    assert_includes err, "the downloaded Ruby does not start: broken"
    assert_empty Dir.children(File.join(share, "rubies"))
  end

  def test_a_second_install_reuses_the_ruby
    install_with(ruby_archive)
    _out, err, status = install_with(ruby_archive)

    assert_equal 0, status.exitstatus, err
    assert_equal 1, asked_for.size
  end

  def test_a_dry_run_writes_nothing_under_the_share
    out, err, status = install_with(ruby_archive, "--dry-run")

    assert_equal 0, status.exitstatus, err
    assert_includes out, "would run it with"
    refute_path_exists share
  end

  private

  def on(system, machine) = write_tool("uname", "#!/bin/sh\ncase \"$1\" in -s) echo #{system} ;; -m) echo #{machine} ;; esac\n")

  def install_with(archive, *arguments, size: File.size(archive), sha: Digest::SHA256.file(archive).hexdigest)
    @sha = sha
    @pins = PLATFORMS.to_h { |platform| [platform, pin(platform, size, sha)] }
    serve(archive)
    extra = { "PLASTIC_RUBY" => nil, "PLASTIC_LOCAL_RELEASE" => release("2.0.3"), "PATH" => tool_path }
    Open3.capture3(environment(extra), "/bin/sh", script, *arguments)
  end

  def teardown
    FileUtils.chmod_R("u+w", @dir)
    super
  end

  def publish(directory, version)
    ReleaseBuild.seal(version, directory, pins: @pins)
    directory
  end

  def pin(platform, size, sha)
    url = (platform == "x86_64-darwin") ? ghcr_url : "https://ruby.test/#{platform}.tar.gz"
    { "key" => "test-ruby", "version" => RUBY_VERSION, "size" => size, "sha256" => sha, "root" => "ruby-test", "url" => url }
  end

  def ghcr_url = "https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:#{@sha}"

  def script
    table = @pins.map { |platform, pin| [platform, *pin.values_at("key", "version", "size", "sha256", "root", "url")].join(" ") }
    path = File.join(@dir, "install.sh")
    File.write(path, File.read(SCRIPT).sub(/^ruby_pins='\n.*?^'\n/m, "ruby_pins='\n#{table.join("\n")}\n'\n"))
    path
  end

  def serve(archive)
    served = FileUtils.mkdir_p(File.join(@dir, "served")).first
    @pins.each_value { |pin| FileUtils.cp(archive, File.join(served, File.basename(pin.fetch("url")))) }
  end

  def ruby_archive = archive_of("ruby") { |bin| executable(File.join(bin, "ruby"), "#!/bin/sh\nexec #{RbConfig.ruby} \"$@\"\n") }

  def archive_of(name)
    source = File.join(@dir, "archive-#{name}")
    bin = FileUtils.mkdir_p(File.join(source, "ruby-test", "bin")).first
    yield bin
    archive = File.join(@dir, "#{name}.tar.gz")
    system("tar", "-czf", archive, "-C", source, "ruby-test", exception: true)
    archive
  end

  def executable(path, body)
    File.write(path, body)
    File.chmod(0o755, path)
  end

  def tool_path
    toolbox = File.join(@dir, "toolbox")
    FileUtils.mkdir_p(toolbox)
    TOOLS.each do |tool|
      found = ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, tool) }.find { |path| File.executable?(path) }
      link = File.join(toolbox, tool)
      File.symlink(found, link) if found && !File.symlink?(link)
    end
    [@fakebin, toolbox].join(File::PATH_SEPARATOR)
  end

  def fake_curl = <<~RUBY
    #!#{RbConfig.ruby} --disable-gems
    require "fileutils"
    out = ARGV[ARGV.index("-o") + 1]
    url = ARGV.reverse.find { |argument| argument.start_with?("https://") && argument != out }
    header = ARGV.each_cons(2).find { |flag, _value| flag == "-H" }&.last
    File.open("#{@dir}/asked-for", "a") { |log| log.puts([url, header].compact.join(" ")) }
    FileUtils.cp(File.join("#{@dir}/served", File.basename(url)), out)
  RUBY

  def asked_for = File.exist?(File.join(@dir, "asked-for")) ? File.readlines(File.join(@dir, "asked-for"), chomp: true) : []

  def ruby_folder = File.join(share, "rubies", "test-ruby")

  def launch_with_empty_path = Open3.capture2({ "PATH" => "" }, launcher).first
end
