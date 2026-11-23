# frozen_string_literal: true

require "time"
require_relative "../record"

module Plastic
  module Graph
    module Work
      # One unit of work inside an intent. The harness picks `kind`; `claimed_by` names the session that holds a claimed node.
      # `criterion` is the key of the spec's done criterion the node serves,
      # `findings` what the work showed, `seen_at` the last renewal of the claim, `answered_at` when the owner last answered, and `deadline`
      # the minutes a claim may run before `graph ready` reports the node as overdue, or nil for none; each claim is a run.
      #
      #   open -> claimed -> done
      #                   -> failed -> open
      #                   -> needs_info -> open
      #                   -> impeded -> open
      #   open -> removed
      Node = Data.define(:intent_id, :id, :kind, :title, :criterion, :state, :input, :output, :question, :answer,
        :reason, :findings, :updated_at, :origin_id, :claimed_by, :claimed_at, :seen_at, :answered_at, :deadline) do
        include Record

        def refusal(to) = "node #{id} is #{state}; it cannot move to #{to}"

        # An open node that is missing from the intent's ready nodes, because a
        # node it needs is not done.
        def waiting?(ready_nodes) = state == "open" && ready_nodes.none? { |ready| ready.id == id }

        def live? = state != "removed"

        def open? = state == "open"

        # The word and the text a claim leaves in the work log, or nil when the claim leaves none.
        def claim_note(status) = { claimed: ["claimed", title.to_s], capped: ["capped", question.to_s] }[status]

        # Why a claim on this node does not win: another session holds it, or it is in no state to claim.
        def claim_rejection = (state == "claimed") ? :held : :refused

        # Why a claim at `now` cannot even start, or nil when the node is open or its claim has lapsed.
        def rejection_at(now) = (claim_rejection unless open? || lapsed?(now))

        # The ids that find this node and the session that holds its claim, as the claim statements bind them.
        def claim_key = { **to_h.slice(:intent_id, :id), holder: claimed_by }

        def capped?(runs, cap) = open? && runs_after_answer(runs).size >= cap

        # The runs of this node after the owner last answered; all of them when it was never answered.
        def runs_after_answer(runs)
          own = runs.select { |run| run.node_id == id }
          answered = answered_at
          answered ? own.select { |run| run.started_at > answered } : own
        end

        # A claim the holder has not renewed within the lapse, at `now`.
        def lapsed?(now) = state == "claimed" && (last_seen.nil? || last_seen < now - Node::LAPSE)

        # A claim that started more than `deadline` minutes before `now`. A node with no deadline is never overdue.
        def overdue?(now) = state == "claimed" && !deadline.nil? && !claimed_at.to_s.empty? && claimed_for(now) > deadline * 60

        # The seconds since the claim started, at `now`.
        def claimed_for(now) = now - Time.parse(claimed_at)

        # The minutes since the claim started, at `now`, rounded up to the minute the claim is in, so a
        # claim past its deadline always names more minutes than the deadline.
        def claimed_minutes(now) = (claimed_for(now) / 60).ceil

        # The last renewal of the claim, else its start; nil when the claim has neither.
        def last_seen
          stamp = [seen_at, claimed_at].find { |value| !value.to_s.empty? }
          stamp && Time.parse(stamp)
        end

        # The fields of the node as a person reads them: the last renewal in the zone of the machine.
        def shown_fields = { **to_h, seen_at: Plastic.local(seen_at) }

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
