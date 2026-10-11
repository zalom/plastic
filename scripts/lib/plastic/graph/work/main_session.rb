# frozen_string_literal: true

module Plastic
  module Graph
    module Work
      # The delivery steps only the main session takes, each with its command.
      # A dispatched agent takes none of them and reports back instead.
      module MainSession
        STEPS = [
          ["take the delivery lock", "plastic auto ID"],
          ["record each ruling", "plastic intent rule ID TEXT"],
          ["write spec.md and add the work nodes", "plastic node add ID TITLE --criterion KEY"],
          ["claim each node as you dispatch it", "plastic node claim ID NODE"],
          ["judge each node's report and record it", "plastic node done ID NODE TEXT"],
          ["judge the intent", "plastic intent judge ID"],
          ["close the intent after the merge", "plastic intent end ID"]
        ].freeze

        def self.lines(intent_id)
          STEPS.map { |step, command| "main session: #{step} with #{command.sub("ID", intent_id)}" }
        end
      end
    end
  end
end
