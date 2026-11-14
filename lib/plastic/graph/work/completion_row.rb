# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # The close of one intent: who judged it, the criteria and the evidence behind it, and the hash of its outcome.
      CompletionRow = Data.define(:intent_id, :origin_id, :at, :session_id, :judge, :criteria, :evidence, :outcome_sha256) do
        include Record

        def self.stored(hash, intent_id) = from_h(hash).to_h.except(:origin_id).merge(intent_id:)
      end
    end
  end
end
