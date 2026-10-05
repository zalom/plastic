# frozen_string_literal: true

require "digest"
require_relative "install_sh_helper"

# install.sh with no Ruby on PATH: it picks the pinned Ruby for the platform,
# checks it and puts it under the share. The tests run a copy of install.sh
# whose pins name a small Ruby that starts the test's own Ruby, served by a
# fake curl. Fake uname, sysctl and ldd programs stand in for each platform.
module InstallShRubyHelper
  include InstallShHelper

  TOOLS = %w[mktemp rm mkdir ln cat cp dirname basename tar gzip grep wc tr cut sort chmod mv].freeze
  PLATFORMS = %w[arm64-darwin x86_64-darwin x86_64-linux aarch64-linux].freeze

  def setup
    super
    write_tool("curl", fake_curl)
    write_tool("ldd", "#!/bin/sh\necho 'ldd (GNU libc) 2.39'\n")
    on("Linux", "x86_64")
  end

  def teardown
    FileUtils.chmod_R("u+w", @dir)
    super
  end

  def on(system, machine) = write_tool("uname", "#!/bin/sh\ncase \"$1\" in -s) echo #{system} ;; -m) echo #{machine} ;; esac\n")

  def install_with(archive, *arguments, size: File.size(archive), sha: Digest::SHA256.file(archive).hexdigest)
    @sha = sha
    @pins = PLATFORMS.to_h { |platform| [platform, pin(platform, size, sha)] }
    serve(archive)
    extra = { "PLASTIC_RUBY" => nil, "PLASTIC_LOCAL_RELEASE" => release("2.0.3"), "PATH" => tool_path }
    Open3.capture3(environment(extra), "/bin/sh", script, *arguments)
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

  def ruby_archive = @ruby_archive ||= archive_of("ruby") { |bin| executable(File.join(bin, "ruby"), "#!/bin/sh\nexec #{RbConfig.ruby} \"$@\"\n") }

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
