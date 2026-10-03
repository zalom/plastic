# frozen_string_literal: true

module Plastic
  module Graph
    module EvidenceText
      # Classifies source bytes and chooses the appropriate text extractor.
      class TextSource
        MARKUP_EXTENSIONS = %w[.html .htm .xml .svg].freeze

        class << self
          def classify(path, bytes)
            return :attachment unless utf8_text(bytes).valid_encoding? && !bytes.include?("\0")

            (extension(path) == ".pdf") ? :unsupported : :text
          end

          def extract(path, bytes) = extract_with_lines(path, bytes)&.body

          def extract_with_lines(path, bytes)
            return nil unless classify(path, bytes) == :text

            extractor(path).extract(utf8_text(bytes))
          end

          private

          def utf8_text(bytes) = bytes.dup.force_encoding(Encoding::UTF_8)
          def extension(path) = File.extname(path).downcase

          def extractor(path)
            extension = extension(path)
            return MarkupText if MARKUP_EXTENSIONS.include?(extension)
            return RichText if extension == ".rtf"

            PlainText
          end
        end
      end
    end
  end
end
