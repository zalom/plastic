# frozen_string_literal: true

require "minitest/autorun"
require "digest"
require "fileutils"
require "open3"
require "tmpdir"
require_relative "../../scripts/lib/installer_release"

# Runs install.sh against throwaway homes. Releases are built in a temp
# directory with the repository's own installer code inside the archive. A
# fake curl serves the release list and the release files, and a fake
# sha256sum written in Ruby checks the sums, so no test reaches the network
# or depends on the machine's digest tools.
module InstallShHelper
  REPO = File.expand_path("../..", __dir__)
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
    #!/usr/bin/env -S ruby --disable-gems
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

  BUNDLER_ENVIRONMENT = %w[RUBYOPT RUBYLIB BUNDLE_GEMFILE BUNDLE_BIN_PATH BUNDLER_SETUP BUNDLER_VERSION].to_h { |name| [name, nil] }.freeze

  def environment(extra = {})
    BUNDLER_ENVIRONMENT.merge("HOME" => @home, "PATH" => [@fakebin, ENV.fetch("PATH")].join(File::PATH_SEPARATOR)).merge(extra)
  end

  def install(*arguments, **extra)
    Open3.capture3(environment(extra.transform_keys(&:to_s)), "sh", SCRIPT, *arguments)
  end

  def install_local(version, *arguments, **extra) = install(*arguments, PLASTIC_LOCAL_RELEASE: release(version), **extra)

  def run_launcher = Open3.capture2(launcher).first
end
