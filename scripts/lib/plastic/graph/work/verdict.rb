# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # One judge round of an intent: accept or revise, with the findings behind it.
      Verdict = Data.define(:intent_id, :round, :origin_id, :verdict, :findings, :at, :session_id) do
        include Record
      end
      Verdict::VERDICTS = %w[accept revise].freeze
      Verdict::ROUNDS = 2
    end
  end
end
