# frozen_string_literal: true

require "yaml"
require_relative "../../agent_models"
require_relative "mapping"

module Plastic
  class Config
    # Moves the agent settings of an agent file that no longer ships to the
    # agent that replaced it, in each section of the YAML node tree. A
    # section that already names the replacement keeps its own value.
    class AgentRenames
      PARTS = %w[models efforts].freeze

      def self.pairs(node) = node.is_a?(Psych::Nodes::Mapping) ? node.children.each_slice(2).to_a : []

      def self.value(node, key) = pairs(node).find { |name, _value| Mapping.named?(name, key) }&.last

      def initialize(root)
        @root = root
      end

      def apply = agent_maps.flat_map { |map| renamed(Mapping.new(map)) }.uniq

      private

      def sections = [AgentRenames.value(@root, "global"), *AgentRenames.pairs(AgentRenames.value(@root, "harnesses")).map(&:last)]

      def agent_maps
        agents = sections.map { |section| AgentRenames.value(section, "agents") }
        agents.flat_map { |node| PARTS.map { |part| AgentRenames.value(node, part) } }.grep(Psych::Nodes::Mapping).uniq(&:object_id)
      end

      def renamed(mapping) = AgentModels::RENAMED.select { |old, new| mapping.rename(old, new) }.to_a
    end
  end
end
