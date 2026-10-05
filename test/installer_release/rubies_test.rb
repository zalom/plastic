# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseRubiesTest < Minitest::Test
  include ReleaseHelper

  JDX = "https://github.com/jdx/ruby/releases/download/4.0.7-2/ruby-4.0.7.macos.tar.gz"
  GHCR = "https://ghcr.io/v2/homebrew/core/portable-ruby/blobs/sha256:57be"

  def teardown
    InstallerRelease::Rubies.remove(File.join(share, "rubies"))
    super
  end

  def test_installs_a_pinned_ruby_read_only_under_its_key
    ruby = rubies.provide(pin)

    assert_equal File.join(folder, "bin", "ruby"), ruby.path
    assert_equal [false, false], [folder, ruby.path].map { |path| File.writable?(path) }
  end

  def test_leaves_only_the_marked_ruby_folder_behind
    rubies.provide(pin)

    assert_equal [["4.0.7-jdx-2"], "#{pin.fetch("sha256")}\n"], [Dir.children(File.join(share, "rubies")), File.read(File.join(folder, ".plastic-ruby"))]
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

  private

  def share = File.join(@root, "share")

  def folder = File.join(share, "rubies", "4.0.7-jdx-2")

  def fetch = (@fetch ||= ReleaseHelper::FetchDouble.new(ruby_archive))

  def rubies(archive: nil, run: ->(_ruby) { "4.0.7" })
    @fetch = ReleaseHelper::FetchDouble.new(archive) if archive
    InstallerRelease::Rubies.new(share, fetch: fetch, run: run)
  end

  def pin = pin_for(ruby_archive)

  def pin_for(archive)
    { "key" => "4.0.7-jdx-2", "version" => "4.0.7", "size" => File.size(archive), "sha256" => Digest::SHA256.file(archive).hexdigest,
      "root" => "ruby-4.0.7", "url" => JDX }
  end

  def ruby_archive
    @ruby_archive ||= tar_archive("ruby.tgz") do |tar|
      tar.mkdir("ruby-4.0.7", 0o755)
      tar.mkdir("ruby-4.0.7/bin", 0o755)
      tar.add_file_simple("ruby-4.0.7/bin/ruby", 0o755, 18) { |io| io.write("#!/bin/sh\necho hi\n") }
    end
  end
end
