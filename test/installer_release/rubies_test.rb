# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseRubiesTest < Minitest::Test
  include ReleaseHelper

  JDX = "https://github.com/jdx/ruby/releases/download/4.0.7-2/ruby-4.0.7.macos.tar.gz"
  GHCR = "https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:57be"

  # Stands in for HttpsFetch: copies a local archive and records each address
  # with its headers.
  class FetchDouble
    attr_reader :asked

    def initialize(archive)
      @archive = archive
      @asked = []
    end

    def download(url, path, headers)
      @asked << [url, headers]
      FileUtils.cp(@archive, path)
      path
    end
  end

  def teardown
    InstallerRelease::Rubies.remove(File.join(share, "rubies"))
    super
  end

  def test_installs_a_pinned_ruby_read_only_under_its_key
    ruby = rubies.provide(pin)

    assert_equal File.join(folder, "bin", "ruby"), ruby.path
    assert_equal "#{pin.fetch("sha256")}\n", File.read(File.join(folder, ".plastic-ruby"))
    assert_equal [false, false], [File.writable?(folder), File.writable?(ruby.path)]
  end

  def test_leaves_only_the_ruby_folder_behind
    rubies.provide(pin)

    assert_equal ["4.0.7-jdx-2"], Dir.children(File.join(share, "rubies"))
  end

  def test_a_second_call_reuses_the_ruby_without_a_download
    2.times { rubies.provide(pin) }

    assert_equal 1, fetch.asked.size
  end

  def test_a_wrong_size_leaves_no_ruby
    error = assert_raises(InstallerRelease::VerificationError) { rubies.provide(pin.merge("size" => pin.fetch("size") + 1)) }

    assert_match(/bytes/, error.message)
    assert_empty Dir.children(File.join(share, "rubies"))
  end

  def test_a_wrong_fingerprint_leaves_no_ruby
    error = assert_raises(InstallerRelease::VerificationError) { rubies.provide(pin.merge("sha256" => "0" * 64)) }

    assert_match(/SHA-256/, error.message)
    assert_empty Dir.children(File.join(share, "rubies"))
  end

  def test_an_archive_with_a_link_leaves_no_ruby
    linked = tar_archive("linked.tgz") { |tar| tar.add_symlink("ruby-4.0.7/bin/ruby", "/bin/sh", 0o755) }

    assert_raises(InstallerRelease::ArchiveError) { rubies(archive: linked).provide(pin_for(linked)) }
    assert_empty Dir.children(File.join(share, "rubies"))
  end

  def test_a_ruby_that_does_not_start_leaves_no_ruby
    error = assert_raises(InstallerRelease::VerificationError) { rubies(run: ->(_ruby) { "boom" }).provide(pin) }

    assert_equal "the Ruby 4.0.7-jdx-2 does not start: boom", error.message
    assert_empty Dir.children(File.join(share, "rubies"))
  end

  def test_refuses_a_folder_that_holds_another_ruby
    FileUtils.mkdir_p(folder)

    error = assert_raises(InstallerRelease::VerificationError) { rubies.provide(pin) }
    assert_equal "#{folder} holds another Ruby; remove that folder and run this again", error.message
  end

  def test_sends_the_anonymous_token_to_the_homebrew_registry_only
    rubies.provide(pin)
    rubies.provide(pin.merge("key" => "4.0.7-homebrew-0", "url" => GHCR))

    assert_equal [[JDX, {}], [GHCR, { "Authorization" => "Bearer QQ==" }]], fetch.asked
  end

  def test_the_default_runner_prints_what_the_ruby_printed
    script = File.join(@root, "ruby")
    File.write(script, "#!/bin/sh\nprintf 4.0.7\n")
    File.chmod(0o755, script)

    assert_equal "4.0.7", InstallerRelease::Rubies::RUN.call(script)
  end

  def test_remove_deletes_a_read_only_tree
    rubies.provide(pin)
    InstallerRelease::Rubies.remove(File.join(share, "rubies"))

    refute_path_exists File.join(share, "rubies")
  end

  def test_names_the_platform_of_each_supported_build
    names = [%w[darwin24 arm64], %w[darwin23 x86_64], %w[linux-gnu x86_64], %w[linux aarch64], %w[freebsd14 amd64]]
      .map { |os, cpu| InstallerRelease::Platform.local("host_os" => os, "host_cpu" => cpu) }

    assert_equal ["arm64-darwin", "x86_64-darwin", "x86_64-linux", "aarch64-linux", nil], names
  end

  def test_the_bundle_program_sits_beside_the_ruby
    assert_equal "/r/bin/bundle", InstallerRelease::Ruby.new("/r/bin/ruby").bundle
  end

  def test_the_choice_takes_the_developer_ruby_first
    choice = InstallerRelease::RubyChoice.new(home: share, override: "/dev/ruby", platform: "arm64-darwin", rubies: rubies)

    assert_equal "/dev/ruby", choice.call(manifest_pinning(pin)).path
    assert_empty fetch.asked
  end

  def test_the_choice_takes_the_build_the_manifest_pins_for_the_platform
    choice = InstallerRelease::RubyChoice.new(home: share, override: "", platform: "arm64-darwin", rubies: rubies)

    assert_equal File.join(folder, "bin", "ruby"), choice.call(manifest_pinning(pin)).path
  end

  def test_the_choice_keeps_the_running_ruby_for_a_release_without_pins
    choice = InstallerRelease::RubyChoice.new(home: share, platform: "arm64-darwin", rubies: rubies)

    assert_equal RbConfig.ruby, choice.call({ "ruby" => { "requirement" => ">= 4.0.0" } }).path
  end

  private

  def share = File.join(@root, "share")

  def folder = File.join(share, "rubies", "4.0.7-jdx-2")

  def fetch = (@fetch ||= FetchDouble.new(ruby_archive))

  def rubies(archive: nil, run: ->(_ruby) { "4.0.7" })
    @fetch = FetchDouble.new(archive) if archive
    InstallerRelease::Rubies.new(share, fetch: fetch, run: run)
  end

  def pin = pin_for(ruby_archive)

  def pin_for(archive)
    { "key" => "4.0.7-jdx-2", "version" => "4.0.7", "size" => File.size(archive), "sha256" => Digest::SHA256.file(archive).hexdigest,
      "root" => "ruby-4.0.7", "url" => JDX }
  end

  def manifest_pinning(build) = { "ruby" => { "builds" => { "arm64-darwin" => build } } }

  def ruby_archive
    @ruby_archive ||= tar_archive("ruby.tgz") do |tar|
      tar.mkdir("ruby-4.0.7", 0o755)
      tar.mkdir("ruby-4.0.7/bin", 0o755)
      tar.add_file_simple("ruby-4.0.7/bin/ruby", 0o755, 18) { |io| io.write("#!/bin/sh\necho hi\n") }
    end
  end
end
