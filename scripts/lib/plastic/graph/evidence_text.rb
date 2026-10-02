# frozen_string_literal: true

require "cgi"

module Plastic
  module Graph
    module EvidenceText
      Extraction = Data.define(:body, :lines)
      MARKUP_EXTENSIONS = %w[.html .htm .xml .svg].freeze
      PASSAGE_SIZE = 1600
      OVERLAP = 200

      def self.classify(path, bytes)
        return :attachment unless utf8?(bytes)

        (File.extname(path).downcase == ".pdf") ? :unsupported : :text
      end

      def self.extract(path, bytes)
        extract_with_lines(path, bytes)&.body
      end

      def self.extract_with_lines(path, bytes)
        source = bytes.dup.force_encoding(Encoding::UTF_8)
        return nil unless classify(path, bytes) == :text

        return markup(source) if MARKUP_EXTENSIONS.include?(File.extname(path).downcase)
        return rtf(source) if File.extname(path).downcase == ".rtf"

        Extraction.new(source, line_numbers(source))
      end

      def self.passages(source)
        text = extraction(source)
        passage_offsets(text.body.length).each_with_index.map { |offset, index| passage(text, offset, index) }
      end

      def self.utf8?(bytes) = bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding? && !bytes.include?("\0")

      def self.rtf(source)
        extract_tokens(rtf_surrogates(source), /\\u(-?\d+)\?|\\'([0-9a-f]{2})|\\[a-z]+-?\d* ?|[{}]/i) do |match|
          decoded_rtf(match)
        end
      end

      def self.markup(source)
        extract_tokens(source, /<(script|style)\b.*?<\/\1>|<[^>]+>|&(?:#\d+|#x[0-9a-f]+|[a-z]+);/mi) do |match|
          match[0].start_with?("&") ? CGI.unescapeHTML(match[0]) : " "
        end
      end

      def self.extract_tokens(source, pattern)
        pieces = []
        cursor = 0
        source.to_enum(:scan, pattern).each do
          match = Regexp.last_match
          append(pieces, source[cursor...match.begin(0)], line_at(source, cursor))
          append(pieces, yield(match), line_at(source, match.begin(0)))
          cursor = match.end(0)
        end
        append(pieces, source[cursor..], line_at(source, cursor))
        normalize(pieces)
      end

      def self.append(pieces, value, line)
        value.each_char do |character|
          pieces << [character, line]
          line += 1 if character == "\n"
        end
      end

      def self.normalize(pieces)
        body, lines = [String.new, []]
        space = nil
        pieces.each { |piece| space = normalize_piece(body, lines, piece, space) }
        Extraction.new(body, lines)
      end

      def self.line_at(source, offset) = source[0...offset].count("\n") + 1

      def self.extraction(source) = source.is_a?(Extraction) ? source : Extraction.new(source, line_numbers(source))

      def self.passage(extraction, offset, index)
        body = extraction.body[offset, PASSAGE_SIZE]
        lines = extraction.lines.slice(offset, body.length)
        { body:, position: index + 1, line_start: lines.first, line_end: lines.last }
      end

      def self.passage_offsets(length) = (0...length).step(PASSAGE_SIZE - OVERLAP)

      def self.decoded_rtf(match)
        return rtf_codepoint(match[1]).chr(Encoding::UTF_8) if match[1]
        return match[2].to_i(16).chr(Encoding::ISO_8859_1).encode(Encoding::UTF_8) if match[2]

        ""
      end

      def self.rtf_codepoint(value)
        number = value.to_i
        number.negative? ? number + 65_536 : number
      end

      def self.rtf_surrogates(source)
        source.gsub(/\\u(-?\d+)\?\\u(-?\d+)\?/) do
          high, low = [Regexp.last_match(1), Regexp.last_match(2)].map { |value| rtf_codepoint(value) }
          surrogate_pair(high, low)
        end
      end

      def self.surrogate_pair(high, low)
        return "" unless high.between?(0xD800, 0xDBFF) && low.between?(0xDC00, 0xDFFF)

        (0x10000 + ((high - 0xD800) << 10) + low - 0xDC00).chr(Encoding::UTF_8)
      end

      def self.normalize_piece(body, lines, piece, space)
        character, line = piece
        return space || line if character.match?(/\s/)

        body << " " and lines << space if space && !body.empty?
        body << character
        lines << line
        nil
      end

      def self.line_numbers(source)
        line = 1
        source.each_char.map do |character|
          current = line
          line += 1 if character == "\n"
          current
        end
      end
    end
  end
end
