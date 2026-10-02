# frozen_string_literal: true

module Plastic
  module Workflows
    # The print lines the show workflows share: one node, one ready node,
    # one ruling.
    module Lines
      def self.node(node) = "node: #{node.id} #{node.state} #{node.title}"

      def self.ready_node(node) = "ready: #{node.id} #{node.title}"

      def self.ruling(ruling, mark: "") = "ruling: #{ruling.id} #{ruling.text}#{mark}"
    end
  end
end
