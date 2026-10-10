# frozen_string_literal: true

require "yaml"
require_relative "layout"
require_relative "mapping"

module Plastic
  class Config
    # The config file as a YAML node tree, so a change keeps the anchors and
    # merge keys the file already holds. A flat file is rewritten in the
    # layout first.
    class Document
      def self.stream(data) = Psych.parse_stream(YAML.dump(data))

      def initialize(path)
        @path = path
      end

      def set(keys, value, harness: nil)
        path = [*(harness ? ["harnesses", harness] : ["global"]), *keys]
        parent(path).assign(path.last, Mapping.node(value))
        save
      end

      def migrate
        return false unless File.file?(@path) && !layout.sectioned?

        @tree = Document.stream(layout.sections)
        save
        true
      end

      private

      def parent(path)
        (1...path.size).reduce(Mapping.new(document.root)) { |mapping, size| descend(mapping, path.first(size)) }
      end

      def descend(mapping, path) = mapping.child(path.last) { inherited(path) }

      def inherited(path)
        value = whole.dig(*path) if whole.is_a?(Hash)
        Mapping.node(value.is_a?(Hash) ? value : {})
      end

      def layout = (@layout ||= Layout.new(resolved))

      def resolved
        YAML.safe_load_file(@path, aliases: true)
      rescue
        {}
      end

      def tree = (@tree ||= (File.file?(@path) && layout.sectioned?) ? parsed : Document.stream(layout.sections))

      def parsed = Psych.parse_stream(File.read(@path)).then { |stream| stream.children.empty? ? Document.stream({}) : stream }

      def document = tree.children.first

      def whole = (@whole ||= document.to_ruby)

      def save = File.write(@path, tree.to_yaml)
    end
  end
end
