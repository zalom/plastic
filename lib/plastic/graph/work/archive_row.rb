# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Work
      # The mark that an intent is archived: when, by which session, and when it was restored.
      ArchiveRow = Data.define(:intent_id, :at, :origin_id, :restored_at, :session_id) do
        include Record

        def restored? = !restored_at.to_s.empty?
      end
    end
  end
end
