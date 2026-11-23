# frozen_string_literal: true

require_relative "../graph/knowledge/ruling_order"

module Plastic
  module Workflows
    # The print lines the show workflows share: one node, one ready node,
    # the rulings of an intent, each superseded one marked.
    module Lines
      CRITERIA = 'the done criteria are the bullets under its "## Done criteria" heading, each written - [c1] text'

      def self.node(node, found_in = nil) = "node: #{node.id} #{node.state} #{node.title}#{holder(node)}#{", found in #{found_in}" if found_in}"

      def self.holder(node)
        return "" unless node.state == "claimed"

        claimant = node.claimed_by
        claimant ? ", held by #{claimant}" : ""
      end

      def self.ready_node(node) = "ready: #{node.id} #{node.title}"

      def self.rulings(rulings)
        superseded = Plastic::Graph::Knowledge::RulingOrder.superseded_ids(rulings)
        Plastic::Graph::Knowledge::RulingOrder.sorted(rulings).map { |ruling| ruling_line(ruling, superseded) }
      end

      def self.ruling_line(ruling, superseded)
        id = ruling.id
        "ruling: #{id} #{ruling.text}#{" (superseded)" if superseded.include?(id)}"
      end
    end
  end
end
