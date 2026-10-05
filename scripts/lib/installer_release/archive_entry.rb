# frozen_string_literal: true

require "fileutils"

module InstallerRelease
  # One tar entry: its name must stay inside the staging directory, and its
  # type must be a plain file, a directory, or a metadata header.
  class ArchiveEntry
    FILE_TYPES = ["0", ""].freeze
    DIRECTORY_TYPE = "5"
    HEADER_TYPES = %w[x g].freeze
    LINK_TYPES = %w[1 2].freeze

    def initialize(entry)
      @entry = entry
      @header = entry.header
      @name = entry.full_name
    end

    def checked_name
      check_path
      raise ArchiveError, "archive contains link #{name}" if LINK_TYPES.include?(type)
      raise ArchiveError, "archive contains special entry #{name}" unless accepted_type?

      name
    end

    def content_bytes = FILE_TYPES.include?(type) ? header.size : 0

    def write_under(root)
      return if HEADER_TYPES.include?(type)

      output = destination(root)
      (type == DIRECTORY_TYPE) ? FileUtils.mkdir_p(output) : write_file(output)
    end

    private

    attr_reader :entry, :header, :name

    def type = header.typeflag

    def accepted_type? = (FILE_TYPES + HEADER_TYPES).include?(type) || type == DIRECTORY_TYPE

    def check_path
      raise ArchiveError, "archive path is unsafe" if name.empty? || name.start_with?("/") || name.include?("\0")
      raise ArchiveError, "archive path escapes staging" if name.split("/").include?("..")
    end

    def destination(root)
      check_path
      base = File.expand_path(root)
      output = File.expand_path(name, base)
      raise ArchiveError, "archive path escapes staging" unless output.start_with?("#{base}/")

      output
    end

    def write_file(output)
      FileUtils.mkdir_p(File.dirname(output))
      File.open(output, "wb", header.mode) { |file| IO.copy_stream(entry, file) }
    end
  end
end
