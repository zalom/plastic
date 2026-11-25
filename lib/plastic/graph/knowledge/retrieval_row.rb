# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Knowledge
      # The saved retrieval context of one intent.
      RetrievalContext = Data.define(:intent_id, :origin_id, :data, :updated_at) do
        include Record
      end

      # The saved retrieval discovery of one intent.
      RetrievalDiscovery = Data.define(:intent_id, :origin_id, :data, :updated_at) do
        include Record
      end
    end
  end
end
