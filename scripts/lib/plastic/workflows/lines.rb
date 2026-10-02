# frozen_string_literal: true

module Plastic
  module Workflows
    # The print lines the show workflows share: one node, one ready node,
    # the rulings of an intent, each superseded one marked.
    module Lines
      def self.node(node) = "node: #{node.id} #{node.state} #{node.title}"

      def self.ready_node(node) = "ready: #{node.id} #{node.title}"

      def self.rulings(rulings)
        superseded = rulings.filter_map(&:supersedes).to_set
        rulings.map { |ruling| "ruling: #{ruling.id} #{ruling.text}#{" (superseded)" if superseded.include?(ruling.id)}" }
      end
    end
  end
end
