# frozen_string_literal: true

require "cgi"

module Plastic
  module Graph
    module EvidenceText
      MARKUP_EXTENSIONS = %w[.html .htm .xml .svg].freeze
      PASSAGE_SIZE = 1600
      OVERLAP = 200

      def self.classify(path, bytes)
        return :attachment unless utf8?(bytes)

        File.extname(path).downcase == ".pdf" ? :unsupported : :text
      end

      def self.extract(path, bytes)
        source = bytes.dup.force_encoding(Encoding::UTF_8)
        return nil unless classify(path, bytes) == :text

        return markup(source) if MARKUP_EXTENSIONS.include?(File.extname(path).downcase)
        return rtf(source) if File.extname(path).downcase == ".rtf"

        source
      end

      def self.passages(body)
        offset = 0
        result = []
        while offset < body.length
          text = body[offset, PASSAGE_SIZE]
          result << { body: text, position: result.size + 1, line_start: line_at(body, offset), line_end: line_at(body, offset + text.length) }
          offset += PASSAGE_SIZE - OVERLAP
        end
        result
      end

      def self.utf8?(bytes) = bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding? && !bytes.include?("\0")
      def self.markup(source) = CGI.unescapeHTML(source.gsub(/<(script|style)\b.*?<\/\1>/mi, "").gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip
      def self.rtf(source)
        source.gsub(/\\u(-?\d+)\?/) { Regexp.last_match(1).to_i.chr(Encoding::UTF_8) }
          .gsub(/\\'([0-9a-f]{2})/i) { Regexp.last_match(1).to_i(16).chr(Encoding::ISO_8859_1).encode(Encoding::UTF_8) }
          .gsub(/\\[a-z]+-?\d* ?/i, "").delete("{}").strip
      end
      def self.line_at(body, offset) = body[0...offset].count("\n") + 1
    end
  end
end
