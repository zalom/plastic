# frozen_string_literal: true

require_relative "../../../layout"

module Plastic
  module Graph
    module Knowledge
      module Repair
        # One change a repair makes in the intent folder `dir`, as the `amended` work log line that records it: `text` says
        # what changed and why, `path` names the file inside the folder, and `at` is the time of an older event the line
        # keeps, or nil for the time of the repair.
        Change = Data.define(:intent_id, :dir, :text, :path, :at) do
          def self.of(kind, dir, what, path, at: nil)
            new(intent_id: SyncSelection.intent_of(dir), dir:, text: "#{what}; #{Layout.amendment_reason(kind)}", path:, at:)
          end

          def line = "amended #{dir}: #{text}"

          def preview = "preview: would amend #{dir}: #{text}"

          # Writes the `amended` line on the work log of the intent through `log`, the log writer of the work graph.
          def write(log) = log.line(intent_id, "amended", text, path:, **(at ? { at: } : {}))
        end
      end
    end
  end
end
