# frozen_string_literal: true

require "json"
require_relative "rewrite"

module Plastic
  module Installations
    # Reads and writes the files an install touches. A write goes through one
    # rename, so a reader never sees half a file.
    module Files
      module_function

      def read_json(path)
        return unless File.exist?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError
        loose_json(File.read(path))
      end

      def loose_json(text)
        JSON.parse(text.gsub(%r{//[^\n]*}, "").gsub(/,(\s*[}\]])/, '\1'))
      rescue JSON::ParserError
        nil
      end

      def write_json(path, data) = Rewrite.replace(resolve(path), "#{JSON.pretty_generate(data)}\n")

      def write_text(path, text) = Rewrite.replace(resolve(path), text)

      def write_if_missing(path, text)
        File.write(path, text) unless File.exist?(path)
      end

      def contained?(path, roots)
        expanded = File.expand_path(path)
        Array(roots).map { |root| File.expand_path(root) }.any? do |root|
          expanded == root || expanded.start_with?(root + File::SEPARATOR)
        end
      end

      def resolve(path)
        File.symlink?(path) ? File.realpath(path) : path
      rescue Errno::ENOENT
        path
      end
    end
  end
end
