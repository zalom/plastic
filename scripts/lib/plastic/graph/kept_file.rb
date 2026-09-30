# frozen_string_literal: true

require_relative "record"

module Plastic
  module Graph
    # A file kept beside an intent that is not Markdown prose, such as an
    # image or a resource: a row of the SQL archive. `name` is its path in
    # the store folder and `data` its bytes, uncompressed.
    KeptFile = Data.define(:name, :mode, :mtime, :sz, :data, :intent_id, :sha256, :origin_id) do
      include Record
    end
  end
end
