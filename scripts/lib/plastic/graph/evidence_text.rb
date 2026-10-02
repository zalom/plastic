# frozen_string_literal: true

require "cgi"

module Plastic
  module Graph
    module EvidenceText
      TEXT_EXTENSIONS = %w[.md .txt .rb .js .json .jsonl .yml .yaml .csv .xml .svg .html .htm .rtf].freeze
      MARKUP_EXTENSIONS = %w[.html .htm .xml .svg].freeze
      PASSAGE_SIZE = 1600
      OVERLAP = 200

      def self.classify(path, bytes)
        return :attachment unless utf8?(bytes)

        TEXT_EXTENSIONS.include?(File.extname(path).downcase) ? :text : :unsupported
      end

      def self.extract(path, bytes)
        source = bytes.dup.force_encoding(Encoding::UTF_8)
        return nil unless classify(path, bytes) == :text

        MARKUP_EXTENSIONS.include?(File.extname(path).downcase) ? markup(source) : rtf(source)
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
      def self.rtf(source) = source.gsub(/\\[a-z]+-?\d* ?/i, "").delete("{}").gsub(/\s+/, " ").strip
      def self.line_at(body, offset) = body[0...offset].count("\n") + 1
    end
  end
end
