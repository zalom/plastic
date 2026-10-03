# frozen_string_literal: true

require "digest"
require "fileutils"

module Plastic
  module RetrievalBenchmark
    # Generates deterministic public documents for retrieval benchmarks.
    class Corpus
      DOCUMENT_BYTES = 4_096
      TEXT = "public benchmark prose Živjeli common retrieval evidence.\n"

      def initialize(directory, target_bytes, stores)
        @directory = directory
        @target_bytes = target_bytes
        @stores = stores
      end

      def generate
        FileUtils.mkdir_p(@directory)
        paths = @stores.times.flat_map { |index| write_store(index, bytes_for_store(index)) }
        receipt(paths)
      end

      private

      def bytes_for_store(index)
        @target_bytes / @stores + ((index < @target_bytes % @stores) ? 1 : 0)
      end

      def write_store(index, bytes)
        directory = File.join(@directory, "store-#{index + 1}")
        FileUtils.mkdir_p(directory)
        document_sizes(bytes).each_with_index.map do |size, document_index|
          path = File.join(directory, format("document-%05d.md", document_index + 1))
          File.write(path, public_text(size, index, document_index), encoding: "UTF-8")
          path
        end
      end

      def document_sizes(bytes)
        Array.new(bytes / DOCUMENT_BYTES, DOCUMENT_BYTES).tap do |sizes|
          sizes << bytes % DOCUMENT_BYTES unless (bytes % DOCUMENT_BYTES).zero?
        end
      end

      def public_text(size, store_index, document_index)
        header = "store#{store_index + 1} document#{document_index + 1} rare-store-#{store_index + 1}.\n"
        fill = TEXT * ((size - header.bytesize) / TEXT.bytesize)
        header + fill + ("x" * (size - header.bytesize - fill.bytesize))
      end

      def receipt(paths)
        digest = Digest::SHA256.new
        paths.each { |path| digest.update(File.binread(path)) }
        { "bytes" => paths.sum { |path| File.size(path) }, "documents" => paths.length,
          "stores" => paths.map { |path| File.basename(File.dirname(path)) }.uniq, "files" => paths,
          "sha256" => digest.hexdigest }
      end
    end
  end
end
