# frozen_string_literal: true

require "yaml"
require_relative "tree"
require_relative "mapping"
require_relative "agent_renames"

module Plastic
  class Config
    # The config file as a YAML node tree, so a change keeps the anchors and
    # merge keys the file already holds. A flat file is rewritten in the
    # layout first.
    class Document
      def initialize(path)
        @path = path
        @file = Tree.new(path)
      end

      def set(keys, value, harness: nil)
        path = [*(harness ? ["harnesses", harness] : ["global"]), *keys]
        parent(path).assign(path.last, Mapping.node(value))
        save
      end

      def migrate
        layout = @file.layout
        return false unless File.file?(@path) && !layout.sectioned?

        @tree = Tree.stream(layout.sections)
        save
        true
      end

      def upgrade
        migrate
        rename_agents
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

      def tree = (@tree ||= @file.stream)

      def document = tree.children.first

      def whole = (@whole ||= document.to_ruby)

      def save = File.write(@path, tree.to_yaml)
    end
  end
end
