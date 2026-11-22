# frozen_string_literal: true

require_relative "../graph/knowledge/ruling_order"

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

      # One run of a node: its agent, the harness and the session that claimed it, how it ended, then what the harness record held
      # (the worker, the model, the tokens and the cost) and what it did not.
      def self.run(run)
        state = run.open? ? "open" : run.result
        head = "run: #{run.node_id} ##{run.number} agent #{run.agent.to_s.empty? ? "none" : run.agent}, #{harness(run)}, #{state}"
        [head, usage(run), run.usage_note].reject { |part| part.to_s.empty? }.join("; ")
      end

      def self.harness(run) = run.harness.to_s.empty? ? "session #{run.session_id}" : "#{run.harness} session #{run.session_id}"

      def self.usage(run)
        figures = [run.model, tokens(run), (format("$%.2f", run.cost_usd) if run.cost_usd), ("worker #{run.worker_session}" unless run.worker_session.to_s.empty?)]
        figures.compact.join(", ")
      end

      def self.tokens(run)
        counts = { "in" => run.input_tokens, "out" => run.output_tokens, "cache read" => run.cache_read_tokens, "cache write" => run.cache_write_tokens }
        counts.filter_map { |name, count| "#{count} #{name}" if count }.join(", ").then { |text| text unless text.empty? }
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
