# frozen_string_literal: true

module Plastic
  module Graph
    module Retrieval
      class Evidence
        module Text
          # Classifies source bytes and chooses the appropriate text extractor.
          class TextSource
            MARKUP_EXTENSIONS = %w[.html .htm .xml .svg].freeze

            def initialize(path, bytes)
              @path = path
              @bytes = bytes
            end

            def classify
              return :attachment unless utf8_text.valid_encoding? && !@bytes.include?("\0")

              (extension == ".pdf") ? :unsupported : :text
            end

            def extract = extract_with_lines&.body

            def extract_with_lines
              return nil unless classify == :text

              extractor.extract(utf8_text)
            end

            private

            def utf8_text = @bytes.dup.force_encoding(Encoding::UTF_8)
            def extension = File.extname(@path).downcase

            def extractor
              return MarkupText if MARKUP_EXTENSIONS.include?(extension)
              return RichText if extension == ".rtf"

              PlainText
            end
          end
        end
      end
    end
  end
end
