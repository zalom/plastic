# frozen_string_literal: true

require "fileutils"
require "rubygems/package"
require "tmpdir"
require "zlib"

module InstallerRelease
  class ArchiveError < StandardError; end

  class Archive
    DEFAULT_MAX_BYTES = 200 * 1024 * 1024
    DEFAULT_MAX_ENTRIES = 10_000
    ACCEPTED_TYPES = ["0", "", "5", "x", "g"].freeze

    def initialize(path, max_bytes: DEFAULT_MAX_BYTES, max_entries: DEFAULT_MAX_ENTRIES)
      @path = path
      @max_bytes = max_bytes
      @max_entries = max_entries
      @names = {}
      @content_bytes = 0
      @entry_count = 0
    end

    def inspect!
      fail!("archive exceeds byte limit") if File.size(path) > max_bytes
      read_entries { |entry| inspect_entry!(entry) }
      names.keys
    end

    def extract_to!(destination)
      read_entries { |entry| extract_entry!(entry, destination) }
    end

    private

    attr_reader :content_bytes, :entry_count, :max_bytes, :max_entries, :names, :path

    def read_entries
      Zlib::GzipReader.open(path) { |gzip| Gem::Package::TarReader.new(gzip).each { |entry| yield entry } }
    rescue Zlib::GzipFile::Error, Gem::Package::TarInvalidError => error
      fail!("archive cannot be read: #{error.message}")
    end

    def inspect_entry!(entry)
      name = entry.full_name
      reject_path!(name)
      fail!("archive contains duplicate entry #{name}") if names[name]

      names[name] = true
      count_entry!
      inspect_type!(entry.header.typeflag, name)
      count_content!(entry.header.size, entry.header.typeflag)
    end

    def extract_entry!(entry, destination)
      return if %w[x g].include?(entry.header.typeflag)

      output = destination_for(destination, entry.full_name)
      entry.directory? ? FileUtils.mkdir_p(output) : write_file(entry, output)
    end

    def count_entry!
      @entry_count += 1
      fail!("archive exceeds entry limit") if entry_count > max_entries
    end

    def inspect_type!(type, name)
      fail!("archive contains link #{name}") if %w[1 2].include?(type)
      fail!("archive contains special entry #{name}") unless ACCEPTED_TYPES.include?(type)
    end

    def count_content!(size, type)
      return unless ["0", ""].include?(type)

      @content_bytes += size
      fail!("archive exceeds content limit") if content_bytes > max_bytes
    end

    def write_file(entry, output)
      FileUtils.mkdir_p(File.dirname(output))
      File.open(output, "wb", entry.header.mode) { |file| IO.copy_stream(entry, file) }
    end

    def destination_for(root, name)
      reject_path!(name)
      output = File.expand_path(name, root)
      fail!("archive path escapes staging") unless output.start_with?("#{File.expand_path(root)}/")
      output
    end

    def reject_path!(name)
      fail!("archive path is unsafe") if name.empty? || name.start_with?("/") || name.include?("\0")
      fail!("archive path escapes staging") if name.split("/").include?("..")
    end

    def fail!(message)
      raise ArchiveError, message
    end
  end

  class Staging
    def self.create!(archive:, manifest:, parent:)
      release = manifest.fetch("release")
      Manifest.validate!(manifest, archive: archive, expected_release: release)
      stage = Dir.mktmpdir("plastic-stage-", parent)
      extract_candidate!(archive, stage, release.fetch("version"))
    rescue
      cleanup(stage)
      raise
    end

    def self.extract_candidate!(archive, stage, version)
      unpacked = Archive.new(archive)
      unpacked.inspect!
      unpacked.extract_to!(stage)
      candidate = File.join(stage, "package")
      Candidate.validate!(candidate, version)
      candidate
    end

    def self.cleanup(stage)
      FileUtils.remove_entry(stage) if defined?(stage) && stage && File.exist?(stage)
    end
  end

  class Candidate
    def self.validate!(path, version)
      executable = File.join(path, "bin", "plastic")
      version_path = File.join(path, "VERSION")
      Manifest.fail!("candidate has no Plastic launcher") unless File.file?(executable) && File.executable?(executable)
      Manifest.fail!("candidate has no version") unless File.file?(version_path)
      Manifest.fail!("candidate version does not match") unless File.read(version_path).strip == version

      true
    end
  end
end
