# frozen_string_literal: true

require "time"
require_relative "../record"

module Plastic
  module Graph
    module Work
      # One unit of work inside an intent. The harness picks `kind`; `claimed_by` names the session that holds a claimed node.
      # `criterion` is the key of the spec's done criterion the node serves,
      # `findings` what the work showed, and `seen_at` the last renewal of the claim; each claim is a run.
      #
      #   open -> claimed -> done
      #                   -> failed -> open
      #                   -> needs_info -> open
      #                   -> impeded -> open
      #   open -> removed
      Node = Data.define(:intent_id, :id, :kind, :title, :criterion, :state, :input, :output, :question, :answer,
        :reason, :judge, :verdict, :findings, :updated_at, :origin_id, :claimed_by, :claimed_at, :seen_at) do
        include Record

        def refusal(to) = "node #{id} is #{state}; it cannot move to #{to}"

        # An open node that is missing from the intent's ready nodes, because a
        # node it needs is not done.
        def waiting?(ready_nodes) = state == "open" && ready_nodes.none? { |ready| ready.id == id }

        def live? = state != "removed"

        # A claim the holder has not renewed within the lapse, at `now`.
        def lapsed?(now) = state == "claimed" && Time.parse(seen_at || claimed_at) < now - Node::LAPSE

        def held_by?(session) = state == "claimed" && claimed_by == session

        def serves?(key) = criterion == key

        def keyed_label = "#{id} (#{criterion || "no key"})"

        def bullet = "- #{keyed_label}"

        def evidence = "#{id}: #{findings.strip}"

        def changed_at = updated_at && Time.parse(updated_at)

        # A done node with nonempty findings.
        def verified? = state == "done" && !findings.to_s.strip.empty?
      end
      Node::LAPSE = 900
      Node::KINDS = %w[orchestrator work retrieval].freeze
      Node::STATES = %w[open claimed done failed needs_info impeded removed].freeze
    end
  end
end
