# frozen_string_literal: true

require_relative "../../../layout"

module Plastic
  module Graph
    module Knowledge
      module Resources
        # One link that a repair rewrites in a core file of the intent folder `dir`. `change` holds the old
        # and the new link, and `body` the new text of the file. A closed intent gets an `amended` work log line for each,
        # and the row of that line keeps the exact old and new link as its `old_text` and `new_text`.
        Amendment = Data.define(:intent_id, :dir, :rel, :change, :body) do
          # The text of the work log line: the file, the old link, the new link and the reason the layout gives.
          def text = "#{rel}: link #{change}; #{Layout.amendment_reason(:link)}"

          def line = "amended #{dir}/#{text}"

          def preview = "preview: would amend #{dir}/#{text}"

          # Writes the `amended` line on the work log of the intent through `log`, the log writer of the work graph.
          def write(log) = log.line(intent_id, "amended", text, path: rel, body:, old_text: change.was, new_text: change.now)
        end
      end
    end
  end
end
