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
        end

        # The words that refuse the first claim, or nil when the claim may go on or is not the first.
        def problem
          return nil unless first_claim?

          blocking = findings.blocking
          return nil if blocking.empty?

          "the graph of intent #{@intent.id} has a finding that stops the first claim: #{blocking.map { |finding| "#{finding.text}; repair: #{finding.repair}" }.join("; ")}"
        end

        # One `finding:` line for each finding, each followed by its repair or its hand edit.
        def lines
          findings.with_repairs.flat_map do |finding|
            ["finding: #{finding.text}", finding.repair ? "repair: #{finding.repair}" : "hand edit: #{finding.hand}"]
          end
        end

        private

        def first_claim? = @retrieval.structure.runs(@intent.id).empty?

        def findings
          @findings ||= Knowledge::Findings.new(@retrieval, @intent.id, schemas: Schemas.new(Knowledge::StoreFolder.new(@root), @intent.dir))
        end
      end
    end
  end
end
