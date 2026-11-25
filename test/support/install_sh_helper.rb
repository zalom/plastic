# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require_relative "child_process"
require "tmpdir"
require_relative "../../bin/lib/release_build"

# Runs install.sh against throwaway homes. Releases are built in a temp
# directory with the repository's own installer code inside the archive. A
# fake curl serves the release list and the release files, and a fake
# sha256sum written in Ruby checks the sums, so no test reaches the network
# or depends on the machine's digest tools.
module InstallShHelper
  REPO = File.expand_path("../..", __dir__)
  SCRIPT = File.join(REPO, "install.sh")
  INSTALLER_FILES = File.read(SCRIPT)[/^tar -xzf .*\/boot" (.*)$/, 1].to_s.split.map { |path| path.delete_prefix("package/") }.freeze

  def setup
    @dir = Dir.mktmpdir("plastic-install-sh")
    @home = File.join(@dir, "home")
    @fakebin = File.join(@dir, "fakebin")
    FileUtils.mkdir_p([@home, @fakebin])
    write_tool("sha256sum", FAKE_SHA256SUM)
    write_tool("git", "#!/bin/sh\necho git version 2.50.0\n")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  FAKE_SHA256SUM = <<~RUBY
    #!#{RbConfig.ruby} --disable-gems
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
    yield File.join(directory, "package") if block_given?
    ChildProcess.system("tar", "-czf", File.join(directory, "plastic.tgz"), "-C", directory, "package", exception: true)
    publish(directory, version)
  end

  def publish(directory, version)
    ReleaseBuild.seal(version, directory)
    directory
  end

  def write_package(package, version)
    INSTALLER_FILES.each do |path|
      FileUtils.mkdir_p(File.dirname(File.join(package, path)))
      FileUtils.cp_r(File.join(REPO, path), File.join(package, path))
    end
    FileUtils.mkdir_p(File.join(package, "exe"))
    File.write(File.join(package, "VERSION"), "#{version}\n")
    File.write(File.join(package, "exe", "plastic"), fake_launcher(version))
    File.chmod(0o755, File.join(package, "exe", "plastic"))
  end

  def fake_launcher(version) = <<~RUBY
    #!/usr/bin/env ruby
    puts(ARGV == %w[version --json] ? '{"result":{"version":"#{version}"}}' : "#{version}")
  RUBY

  # PLASTIC_RUBY runs the installer with the test's Ruby, so only the tests
  # of the Ruby download make install.sh fetch one.
  def environment(extra = {})
    { "HOME" => @home, "PLASTIC_RUBY" => RbConfig.ruby, "PATH" => [@fakebin, ChildProcess::PATH].join(File::PATH_SEPARATOR) }.merge(extra)
  end

  def install(*arguments, **extra)
    ChildProcess.capture3(environment(extra.transform_keys(&:to_s)), "sh", SCRIPT, *arguments)
  end

  def install_local(version, *arguments, **extra) = install(*arguments, PLASTIC_LOCAL_RELEASE: release(version), **extra)

  def run_launcher = ChildProcess.capture2(launcher).first

  # A fake curl that answers the GitHub release list with these versions, each carrying the three
  # release files, and the versions of partial: (a hash of version to file names) with only the files named,
  # and serves a release file from the throwaway release folder.
  def serve_releases(*versions, partial: {})
    feed = File.join(@dir, "releases.json")
    assets = %w[plastic.tgz plastic.tgz.sha256 plastic.manifest.json].map { |name| { "name" => name } }
    listed = versions.map { |version| [version, assets] } + partial.map { |version, names| [version, names.map { |name| { "name" => name } }] }
    File.write(feed, JSON.generate(listed.map { |version, files| { "tag_name" => "v#{version}", "assets" => files } }))
    write_tool("curl", fake_curl(feed))
  end

  def fake_curl(feed) = <<~RUBY
    #!#{RbConfig.ruby} --disable-gems
    url = ARGV.find { |argument| argument.start_with?("https://") }
    if url.include?("api.github.com")
      print(File.read(#{feed.dump}))
      exit
    end
    source = File.join(#{File.join(@dir, "releases").dump}, *url.split("/").last(2))
    exit(22) unless File.file?(source)
    File.binwrite(ARGV.fetch(ARGV.index("-o") + 1), File.binread(source))
  RUBY
end
