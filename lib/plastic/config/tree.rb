# frozen_string_literal: true

require "yaml"
require_relative "layout"

module Plastic
  class Config
    # The config file as a YAML node stream: the file as written when it is in
    # the layout, otherwise the sections it moves to.
    class Tree
      def self.stream(data) = Psych.parse_stream(YAML.dump(data))

      def initialize(path)
        @path = path
      end

      def layout = (@layout ||= Layout.new(resolved))

      def stream = kept? ? Psych.parse_stream(File.read(@path)) : Tree.stream(layout.sections)

      private

      def resolved
        YAML.safe_load_file(@path, aliases: true)
      rescue
        nil
      end

      def kept? = resolved.is_a?(Hash) && layout.sectioned?
    end
  end
end
