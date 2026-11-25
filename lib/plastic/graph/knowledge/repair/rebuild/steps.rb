# frozen_string_literal: true

require_relative "node_draft"
require_relative "checklist"

module Plastic
  module Graph
    module Knowledge
      module Repair
        module Rebuild
          # The nodes of one old intent. A step of the checklist, or of the plan when the checklist lists none, is a node in
          # the state its tick and the intent give. A brief goes with each step it names; a brief or an evidence file that
          # names no step is a node of its own, in the state of the intent.
          class Steps
            CLOSED = %w[done abandoned].freeze
            NUMBER = /\bACTION[_ -]?(\d+[a-z]?)\b/i
            NOT_TICKED = "Not ticked in the old checklist when the intent closed."
            TICKED = "Ticked done in the old checklist."
            SPARE = "Kept from the old actions folder; the file names no step."

            def initialize(items, briefs, status)
              @items = items
              @briefs = briefs
              @status = status
            end

            def call = @items.map { |item| step(item) } + spare.map { |brief| own(brief) }

            private

            def step(item)
              served = served_by(item)
              state = item.done ? "done" : unticked
              NodeDraft.new(title: item.title, state:, packet: served.reject(&:evidence?).first&.text, findings: findings(state, served), reason: reason(state))
            end

            def served_by(item) = @briefs.select { |brief| brief.number && brief.number == item.title[NUMBER, 1] }

            def unticked = CLOSED.include?(@status) ? "abandoned" : "open"

            def reason(state) = (state == "abandoned") ? NOT_TICKED : nil

            def findings(state, served)
              return unless state == "done"

              served.filter_map { |brief| brief.evidence? ? brief.text : brief.result }.first || TICKED
            end

            def spare = @briefs.select { |brief| @items.none? { |item| brief.number && brief.number == item.title[NUMBER, 1] } }

            def own(brief)
              state = CLOSED.include?(@status) ? @status : "open"
              evidence = brief.evidence?
              NodeDraft.new(title: brief.heading, state:, packet: evidence ? nil : brief.text, findings: findings_of(brief, state, evidence), reason: reason(state))
            end

            def findings_of(brief, state, evidence)
              return unless state == "done"

              evidence ? brief.text : (brief.result || SPARE)
            end
          end
        end
      end
    end
  end
end
