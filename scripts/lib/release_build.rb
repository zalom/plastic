# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "rubygems/package"
require "zlib"
require_relative "installer_release"

# Builds the three files a GitHub release carries and install.sh downloads:
# plastic.tgz with the files package.json lists under package/, its
# checksum, and the manifest. The publish workflow, CI and the fresh
# install check all build through this class.
class ReleaseBuild
  EXTRA = %w[package.json README.md LICENSE].freeze
  ARCHIVE = "plastic.tgz"

  def self.call(version:, directory:, root:) = new(version, directory, root).call

  def self.seal(version, directory)
    archive = File.join(directory, ARCHIVE)
    File.write("#{archive}.sha256", "#{Digest::SHA256.file(archive).hexdigest}  #{ARCHIVE}\n")
    release = InstallerRelease::Manifest.identity(version).merge("platform" => "universal", "architecture" => "universal")
    InstallerRelease::Manifest.write(File.join(directory, "plastic.manifest.json"), archive:, release:)
  end

  # One file of the archive, written under package/ with its mode.
  Entry = Data.define(:name, :content, :mode) do
    def write_to(tar) = tar.add_file_simple("package/#{name}", mode, content.bytesize) { |io| io.write(content) }
  end

  def initialize(version, directory, root)
    @version = version
    @directory = directory
    @root = root
  end

  def call
    FileUtils.mkdir_p(directory)
    Zlib::GzipWriter.open(File.join(directory, ARCHIVE)) { |gzip| write_tar(gzip) }
    self.class.seal(version, directory)
  end

  private

  attr_reader :version, :directory, :root

  def write_tar(gzip)
    tar = Gem::Package::TarWriter.new(gzip)
    entries.each { |entry| entry.write_to(tar) }
    tar.close
  end

  def entries
    package_files.map { |name| file_entry(name) } << Entry.new("VERSION", "#{version}\n", 0o644)
  end

  def file_entry(name)
    path = source(name)
    Entry.new(name, File.binread(path), File.stat(path).mode & 0o777)
  end

  def source(name) = File.join(root, name)

  def package_files
    listed = JSON.parse(File.read(source("package.json"))).fetch("files") - ["VERSION"]
    (listed.flat_map { |entry| expand(entry) } + EXTRA).uniq.sort
  end

  def expand(entry)
    return [entry] unless entry.end_with?("/")

    Dir.glob("#{entry}**/*", File::FNM_DOTMATCH, base: root).select { |name| File.file?(source(name)) }
  end
end
