# frozen_string_literal: true

require "json"
require "rubygems/package"
require "zlib"

# Writes plastic.tgz: the files package.json lists, plus EXTRA and a VERSION
# file, each under package/ with its mode.
class ReleaseArchive
  EXTRA = %w[package.json README.md LICENSE].freeze

  # One file of the archive, written under package/ with its mode.
  Entry = Data.define(:name, :content, :mode) do
    def write_to(tar) = tar.add_file_simple("package/#{name}", mode, content.bytesize) { |io| io.write(content) }
  end

  def self.write(path, version:, root:) = new(version, root).write(path)

  def initialize(version, root)
    @version = version
    @root = root
  end

  def write(path)
    Zlib::GzipWriter.open(path) { |gzip| write_tar(gzip) }
  end

  private

  attr_reader :version, :root

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
