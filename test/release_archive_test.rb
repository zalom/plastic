# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../scripts/lib/release_archive"

class ReleaseArchiveTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("release-archive")
    write_file("package.json", JSON.generate("files" => ["bin/plastic", "lib/", "VERSION"]))
    write_file("README.md", "# Plastic\n")
    write_file("LICENSE", "MIT\n")
    write_file("bin/plastic", "#!/bin/sh\n", mode: 0o755)
    write_file("lib/plastic.rb", "\n")
    write_file("lib/.keep", "")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def write_file(name, content, mode: 0o644)
    path = File.join(@root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    File.chmod(mode, path)
  end

  def entries
    archive = File.join(@root, "plastic.tgz")
    ReleaseArchive.write(archive, version: "2.0.3", root: @root)
    Zlib::GzipReader.open(archive) do |gzip|
      Gem::Package::TarReader.new(gzip).to_h { |entry| [entry.full_name, [entry.header.mode, entry.read.to_s]] }
    end
  end

  def test_the_listed_files_a_folder_with_its_dotfiles_and_the_extra_files_are_under_package
    names = %w[LICENSE README.md VERSION bin/plastic lib/.keep lib/plastic.rb package.json].map { |name| "package/#{name}" }

    assert_equal names.sort, entries.keys.sort
  end

  def test_the_version_entry_carries_the_given_version
    assert_equal [0o644, "2.0.3\n"], entries.fetch("package/VERSION")
  end

  def test_each_file_keeps_its_mode
    assert_equal [0o755, 0o644], entries.values_at("package/bin/plastic", "package/README.md").map(&:first)
  end
end
