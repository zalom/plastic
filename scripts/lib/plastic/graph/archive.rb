# frozen_string_literal: true

require_relative "record"

module Plastic
  module Graph
    # One intent held off the checkout: the folder is gone from disk, and its
    # printed rows are gone too, but its rows stay. `restored_at` nil means
    # the intent is archived now.
    Archive = Data.define(:intent_id, :at, :origin_id, :restored_at, :session_id) do
      include Record
    end
  end
end
