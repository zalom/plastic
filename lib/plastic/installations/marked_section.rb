# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "files"

module Plastic
  module Installations
    # A block Plastic owns inside an instruction file the person also edits.
    # The begin marker carries a hash of the body, so a reader can tell a
    # current block from a stale one. The two blocks Plastic writes have a
    # marker pair each, because the two files can be one file behind a link.
    class MarkedSection
      Kind = Data.define(:begin_prefix, :end_marker) do
        def pattern = /^#{Regexp.escape(begin_prefix)}.*?-->\n.*?\n#{Regexp.escape(end_marker)}\n?/m
      end

      CODEX = Kind.new("<!-- BEGIN PLASTIC INTEGRATION", "<!-- END PLASTIC INTEGRATION -->")
      CLAUDE = Kind.new("<!-- BEGIN PLASTIC COMPACT", "<!-- END PLASTIC COMPACT -->")

      def initialize(kind, body)
        @kind = kind
        @body = body
      end

      # Returns :created, :appended, :replaced or :refused. A begin marker
      # with no end marker is refused, and nothing is written.
      def inject(path)
        path = Files.resolve(path)
        return create(path) unless File.exist?(path)

        content = File.read(path)
        opened = content.include?(@kind.begin_prefix)
        return :refused if opened && !content.include?(@kind.end_marker)

        opened ? replace(path, content) : append(path, content)
      end

      private

      def section
        hash = Digest::SHA256.hexdigest(@body)[0, 12]
        "#{@kind.begin_prefix} hash:#{hash} -->\n#{@body.strip}\n#{@kind.end_marker}\n"
      end

      def create(path)
        FileUtils.mkdir_p(File.dirname(path))
        Files.write_text(path, section)
        :created
      end

      def replace(path, content)
        Files.write_text(path, content.sub(@kind.pattern) { section })
        :replaced
      end

      def append(path, content)
        base = content.end_with?("\n") ? content : "#{content}\n"
        Files.write_text(path, "#{base}\n#{section}")
        :appended
      end
    end
  end
end
