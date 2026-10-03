# frozen_string_literal: true

require "fileutils"
require "rubygems/package"
require "zlib"
require_relative "archive_entry"

module InstallerRelease
  class ArchiveError < StandardError; end

  # A gzipped tar read twice: once to check every entry against the limits,
  # and once to write the entries that passed into a staging directory.
  class Archive
    Limits = Data.define(:bytes, :entries)
    DEFAULT_LIMITS = Limits.new(bytes: 200 * 1024 * 1024, entries: 10_000)

    def initialize(path, limits: DEFAULT_LIMITS)
      @path = path
      @limits = limits
    end

    def entry_names
      raise ArchiveError, "archive exceeds byte limit" if File.size(path) > limits.bytes

      tally = Tally.new(limits)
      each_entry { |entry| tally.add(ArchiveEntry.new(entry)) }
      tally.names
    end

    def extract_to(destination)
      each_entry { |entry| ArchiveEntry.new(entry).write_under(destination) }
    end

    private

    attr_reader :limits, :path

    def each_entry(&)
      Zlib::GzipReader.open(path) { |gzip| Gem::Package::TarReader.new(gzip).each(&) }
    rescue Zlib::GzipFile::Error, Gem::Package::TarInvalidError => error
      raise ArchiveError, "archive cannot be read: #{error.message}"
    end
  end

  # Counts the entries and content bytes of one archive and refuses a
  # duplicate name or a count over the limits.
  class Tally
    def initialize(limits)
      @limits = limits
      @seen = {}
      @bytes = 0
    end

    def add(entry)
      name = entry.checked_name
      raise ArchiveError, "archive contains duplicate entry #{name}" if @seen.key?(name)

      @seen[name] = true
      raise ArchiveError, "archive exceeds entry limit" if @seen.size > @limits.entries

      add_bytes(entry.content_bytes)
    end

    def names = @seen.keys

    private

    def add_bytes(count)
      @bytes += count
      raise ArchiveError, "archive exceeds content limit" if @bytes > @limits.bytes
    end
  end
end
