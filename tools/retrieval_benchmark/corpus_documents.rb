# frozen_string_literal: true

require "digest"
require "fileutils"

module Plastic
  module RetrievalBenchmark
    CORPUS_DOCUMENT_BYTES = 4_096
    CORPUS_TEXT = "public benchmark prose Živjeli common retrieval evidence.\n"

    # Splits a store's target bytes into complete deterministic documents.
    CorpusDocumentSizes = Data.define(:target_bytes) do
      def values
        quotient, remainder = target_bytes.divmod(CORPUS_DOCUMENT_BYTES)
        Array.new(quotient, CORPUS_DOCUMENT_BYTES).tap { |sizes| sizes << remainder unless remainder.zero? }
      end
    end

    # Builds one deterministic UTF-8 corpus document with an exact byte size.
    CorpusDocumentBody = Data.define(:size, :store_index, :document_index) do
      def text
        fill_count, tail_bytes = remaining.divmod(CORPUS_TEXT.bytesize)
        header + (CORPUS_TEXT * fill_count) + ("x" * tail_bytes)
      end

      def store_number = store_index + 1
      def header = "store#{store_number} document#{document_index + 1} rare-store-#{store_number}.\n"
      def remaining = size - header.bytesize
    end

    # Summarizes the generated corpus in deterministic file order.
    CorpusReceipt = Data.define(:paths) do
      def to_h = { "bytes" => bytes, "documents" => paths.length, "stores" => stores, "files" => paths, "sha256" => digest }

      def bytes = paths.sum { |path| File.size(path) }

      def stores = paths.map { |path| File.basename(File.dirname(path)) }.uniq

      def digest = paths.reduce(Digest::SHA256.new) { |state, path| state.update(File.binread(path)) }.hexdigest
    end

    # Owns one corpus store directory and its deterministic document paths.
    class CorpusStoreDocuments
      def initialize(root, store_index, bytes)
        @directory = File.join(root, "store-#{store_index + 1}")
        @store_index = store_index
        @bytes = bytes
      end

      def write
        FileUtils.mkdir_p(@directory)
        CorpusDocumentSizes.new(@bytes).values.each_with_index.map { |size, index| write_document(size, index) }
      end

      private

      def write_document(size, index)
        path = File.join(@directory, format("document-%05d.md", index + 1))
        File.write(path, CorpusDocumentBody.new(size, @store_index, index).text, encoding: "UTF-8")
        path
      end
    end
  end
end
