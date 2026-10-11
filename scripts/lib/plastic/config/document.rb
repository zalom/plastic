# frozen_string_literal: true

require "yaml"
require_relative "layout"
require_relative "mapping"
require_relative "agent_renames"

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

      def rename_agents
        renamed = AgentRenames.new(document.root).apply
        save unless renamed.empty?
        renamed
      end

      private

      def parent(path)
        (1...path.size).reduce(Mapping.new(document.root)) { |mapping, size| descend(mapping, path.first(size)) }
      end

      def descend(mapping, path) = mapping.child(path.last) { inherited(path) }

      def inherited(path) = Mapping.node(Layout.within(whole, *path))

      def layout = (@layout ||= Layout.new(resolved))

      def resolved
        YAML.safe_load_file(@path, aliases: true)
      rescue
        nil
      end

      def tree = (@tree ||= kept? ? Psych.parse_stream(File.read(@path)) : Document.stream(layout.sections))

      def kept? = resolved.is_a?(Hash) && layout.sectioned?

      def document = tree.children.first

      def whole = (@whole ||= document.to_ruby)

      def save = File.write(@path, tree.to_yaml)
    end
  end
end
