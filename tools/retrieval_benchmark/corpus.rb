# frozen_string_literal: true

require "digest"
require "fileutils"

module Plastic
  module RetrievalBenchmark
    # Generates deterministic public documents for retrieval benchmarks.
    class Corpus
      DOCUMENT_BYTES = 4_096
      TEXT = "public benchmark prose Živjeli common retrieval evidence.\n"

      # Splits one store's byte budget into complete documents and one remainder.
      DocumentSizes = Data.define(:target_bytes) do
        def values
          quotient, remainder = target_bytes.divmod(DOCUMENT_BYTES)
          Array.new(quotient, DOCUMENT_BYTES).tap { |sizes| sizes << remainder unless remainder.zero? }
        end
      end

      # Builds one deterministic UTF-8 document with its exact requested size.
      DocumentBody = Data.define(:size, :store_index, :document_index) do
        def text
          header + fill + ("x" * remaining_bytes)
        end

        private

        def store_number = store_index + 1
        def document_number = document_index + 1
        def header = "store#{store_number} document#{document_number} rare-store-#{store_number}.\n"
        def remaining = size - header.bytesize
        def fill = TEXT * (remaining / TEXT.bytesize)
        def remaining_bytes = remaining - fill.bytesize
      end

      # Summarizes the generated public corpus without changing its file order.
      Receipt = Data.define(:paths) do
        def to_h = { "bytes" => bytes, "documents" => paths.length, "stores" => stores, "files" => paths, "sha256" => digest }

        private

        def bytes = paths.sum { |path| File.size(path) }

        def stores = paths.map { |path| File.basename(File.dirname(path)) }.uniq

        def digest
          sha256 = Digest::SHA256.new
          paths.each { |path| sha256.update(File.binread(path)) }
          sha256.hexdigest
        end
      end

      # Owns the directory and files for one deterministic benchmark store.
      class StoreDocuments
        def initialize(root, store_index, bytes)
          @directory = File.join(root, "store-#{store_index + 1}")
          @store_index = store_index
          @bytes = bytes
        end

        def write
          FileUtils.mkdir_p(@directory)
          DocumentSizes.new(@bytes).values.each_with_index.map { |size, index| write_document(size, index) }
        end

        private

        def write_document(size, index)
          path = File.join(@directory, format("document-%05d.md", index + 1))
          File.write(path, DocumentBody.new(size, @store_index, index).text, encoding: "UTF-8")
          path
        end
      end

      def initialize(directory, target_bytes, stores)
        @directory = directory
        @target_bytes = target_bytes
        @stores = stores
      end

      def generate
        FileUtils.mkdir_p(@directory)
        paths = @stores.times.flat_map { |index| write_store(index, bytes_for_store(index)) }
        Receipt.new(paths).to_h
      end

      private

      def bytes_for_store(index)
        @target_bytes / @stores + ((index < @target_bytes % @stores) ? 1 : 0)
      end

      def write_store(index, bytes)
        StoreDocuments.new(@directory, index, bytes).write
      end
    end
  end
end
