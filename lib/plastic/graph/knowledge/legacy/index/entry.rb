# frozen_string_literal: true

require_relative "../../luhmann_id"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        module Index
          # One intent of the file: its status and what its line adds.
          Entry = Data.define(:intent_id, :title, :dir, :status, :disposition, :reason, :closed_at)

          # The intent row an entry imports as.
          class Entry
            # `front` holds the fields at the head of the intent's own file.
            def row(front, now)
              { intent_id:, parent_id: LuhmannId.parent_of(intent_id), slug: File.basename(dir).split("--", 2).last,
                title:, kind: front["kind"], status:, disposition:, reason:, opened_at: front["created"], closed_at:,
                updated_at: now }
            end
          end
        end
      end
    end
  end
end
