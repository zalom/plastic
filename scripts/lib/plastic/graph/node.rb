# frozen_string_literal: true

require_relative "record"

module Plastic
  module Graph
    # One unit of work inside an intent. The harness picks `kind` and `by`.
    # `criterion` says what done means, `judge` what judged it, `verdict`
    # accept or revise, and `retries` counts the claims.
    Node = Data.define(:intent_id, :id, :kind, :title, :criterion, :state, :by, :input, :output, :question, :answer,
      :reason, :judge, :verdict, :findings, :retries, :updated_at, :origin_id) do
      include Record
    end
  end
end
