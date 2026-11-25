# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # One intent's membership of a named cluster. Clusters are names only.
      Cluster = Data.define(:name, :intent_id, :origin_id) do
        include Record
      end
    end
  end
end
