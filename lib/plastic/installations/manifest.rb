# frozen_string_literal: true

require "digest"
require_relative "../clock"
require_relative "files"

module Plastic
  module Installations
    # The record of the files one install wrote: each path with the hash of
    # its text. The record is what a prune, a restore and a removal read.
    class Manifest
      def initialize(path)
        @path = path
      end

      def files = entries.keys

      def empty? = entries.empty?

      def write(paths)
        listed = paths.select { |path| File.exist?(path) }.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
        Files.write_json(@path, { "version" => "1", "created" => Plastic.now, "files" => listed })
        self
      end

      def verified?
        !entries.empty? && entries.all? { |path, hash| File.exist?(path) && Digest::SHA256.file(path).hexdigest == hash }
      end

      private

      def entries
        data = Files.read_json(@path)
        data.is_a?(Hash) ? Hash(data["files"]) : {}
      end
    end
  end
end
