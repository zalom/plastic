# frozen_string_literal: true

require_relative "../knowledge/findings"
require_relative "../knowledge/store_folder"
require_relative "schemas"

module Plastic
  module Graph
    module Work
      # The check of an intent's graph before work starts, at the plan's approval and at the first claim. It reuses
      # the findings of `plastic graph check`: a loop and a need on a removed node stop the first claim, and every
      # other finding is printed and stops nothing.
      class StartCheck
        def initialize(retrieval, intent, root)
          @retrieval = retrieval
          @intent = intent
          @root = root
          @first_claim = retrieval.structure.runs(intent.intent_id).empty? # asked once, before the claim writes its run row
        end

        # The words that refuse the first claim, or nil when the claim may go on or is not the first.
        def problem
          return nil unless first_claim?

          blocking = findings.blocking
          return nil if blocking.empty?

          "the graph of intent #{@intent.intent_id} has a finding that stops the first claim: #{blocking.map { |finding| "#{finding.text}; repair: #{finding.repair}" }.join("; ")}"
        end

        # One `finding:` line for each finding, each followed by its repair or its hand edit.
        def lines = findings.with_repairs.flat_map(&:lines)

        # The lines a claim prints: the findings on the first claim of the intent, nothing on a later one.
        def claim_lines = first_claim? ? lines : []

        private

        def first_claim? = @first_claim

        def findings
          @findings ||= Knowledge::Findings.new(@retrieval, @intent.intent_id, schemas: Schemas.new(Knowledge::StoreFolder.new(@root), @intent.dir))
        end
      end
    end
  end
end
