# frozen_string_literal: true

require_relative "evidence_text/extractor"
require_relative "evidence_text/passages"

module Plastic
  module Graph
    # Classifies and extracts text before retrieval stores immutable evidence.
    module EvidenceText
      # Holds extracted text and the original source line for each character.
      Extraction = Data.define(:body, :lines)
      MARKUP_EXTENSIONS = TextSource::MARKUP_EXTENSIONS
      PASSAGE_SIZE = Passages::SIZE
      OVERLAP = Passages::OVERLAP

      module_function

      def classify(...) = TextSource.new(...).classify
      def extract(...) = TextSource.new(...).extract
      def extract_with_lines(...) = TextSource.new(...).extract_with_lines
      def passages(source) = Passages.build(source)
    end
  end
end
