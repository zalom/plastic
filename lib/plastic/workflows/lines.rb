# frozen_string_literal: true

require_relative "../graph/knowledge/ruling_order"

module Plastic
  module Workflows
    # The print lines the show workflows share: one node, one ready node,
    # the rulings of an intent, each superseded one marked.
    module Lines
      CRITERIA = 'the done criteria are the bullets under its "## Done criteria" heading, each written - [c1] text'

      def self.node(node, found_in = nil) = "node: #{node.id} #{node.state} #{node.title}#{holder(node)}#{", found in #{found_in}" if found_in}#{deadline(node.deadline)}"

      def self.deadline(minutes) = minutes ? ", deadline #{minutes(minutes)}" : ""

      # A count of minutes with its unit: 1 minute, 2 minutes.
      def self.minutes(count) = "#{count} minute#{"s" unless count == 1}"

      def self.holder(node)
        return "" unless node.state == "claimed"

        claimant = node.claimed_by
        claimant ? ", held by #{claimant}" : ""
      end

      # One run of a node: its agent, the harness and the session that claimed it, how it ended, then what the harness record held
      # (the worker, the model, the tokens and the cost) and what it did not.
      def self.run_line(run)
        state = run.open? ? "open" : run.result
        head = "run: #{run.node_id} ##{run.number} agent #{agent_name(run.agent)}, #{harness(run.harness.to_s, run.session_id)}, #{state}"
        [head, usage(run), run.usage_note].reject { |part| part.to_s.empty? }.join("; ")
      end

      def self.agent_name(agent) = agent.to_s.empty? ? "none" : agent

      def self.harness(name, session) = name.empty? ? "session #{session}" : "#{name} session #{session}"

      def self.usage(run) = [run.model, tokens(run), cost(run.cost_usd), worker(run.worker_session.to_s)].compact.join(", ")

      def self.cost(usd) = usd&.then { |amount| format("$%.2f", amount) }

      def self.worker(session) = session.empty? ? nil : "worker #{session}"

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
