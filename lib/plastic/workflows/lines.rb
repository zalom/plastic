# frozen_string_literal: true

module Plastic
  module Workflows
    # The print lines the show workflows share: one node, one ready node,
    # the rulings of an intent, each superseded one marked.
    module Lines
      CRITERIA = 'the done criteria are the bullets under its "## Done criteria" heading, each written - [c1] text'

      def self.node(node) = "node: #{node.id} #{node.state} #{node.title}#{holder(node)}"

      def self.holder(node)
        return "" unless node.state == "claimed"

        claimant = node.claimed_by
        claimant ? ", held by #{claimant}" : ""
      end

      def self.ready_node(node) = "ready: #{node.id} #{node.title}"

      def self.rulings(rulings)
        superseded = rulings.filter_map(&:supersedes).to_set
        rulings.sort_by { |ruling| ruling.id[/\d+/].to_i }.map { |ruling| ruling_line(ruling, superseded) }
      end

      def self.ruling_line(ruling, superseded)
        id = ruling.id
        "ruling: #{id} #{ruling.text}#{" (superseded)" if superseded.include?(id)}"
      end
    end
  end
end
