# frozen_string_literal: true

require "yaml"

module Plastic
  class Config
    # One mapping node of the config's YAML tree, written in block style.
    class Mapping
      def self.node(value) = Psych.parse(YAML.dump(value)).root

      def self.named?(node, key) = node.is_a?(Psych::Nodes::Scalar) && node.value == key

      def initialize(node)
        @node = node
        node.style = Psych::Nodes::Mapping::BLOCK
      end

      # The mapping under the key. A key that holds no mapping of its own,
      # such as an alias, gets the one the block returns.
      def child(key)
        current = self[key]
        Mapping.new(current.is_a?(Psych::Nodes::Mapping) ? current : assign(key, yield))
      end

      def assign(key, value)
        children = @node.children
        index = position(key)
        index ? children[index + 1] = value : children.push(Mapping.node(key), value)
        value
      end

      def rename(key, name)
        index = position(key)
        index && replace(index, name)
      end

      private

      def replace(index, name)
        children = @node.children
        position(name) ? children.slice!(index, 2) : children[index].value = name
        true
      end

      def [](key) = position(key)&.then { |index| @node.children[index + 1] }

      def position(key)
        @node.children.each_slice(2).find_index { |name, _| Mapping.named?(name, key) }&.*(2)
      end
    end
  end
end
