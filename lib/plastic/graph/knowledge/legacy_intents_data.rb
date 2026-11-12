# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Knowledge
      # A plan, checklist or action file of an intent's folder, kept whole as old data.
      # `path` is relative to the folder; the body is the file, byte for byte.
      LegacyIntentsData = Data.define(:intent_id, :path, :body, :updated_at, :origin_id) do
        include Record
      end
    end
  end
end
