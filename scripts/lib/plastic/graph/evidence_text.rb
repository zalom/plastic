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

      def classify(path, bytes) = TextSource.classify(path, bytes)
      def extract(path, bytes) = TextSource.extract(path, bytes)
      def extract_with_lines(path, bytes) = TextSource.extract_with_lines(path, bytes)
      def passages(source) = Passages.build(source)
    end
  end
end
