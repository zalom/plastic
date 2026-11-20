# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Resources
        # One link that a sort rewrites in a core file, a note at the root of the intent folder `dir`. `change` holds the old
        # and the new link, and `body` the new text of the file. A closed intent gets an `amended` work log line for each.
        Amendment = Data.define(:intent_id, :dir, :rel, :change, :body) do
          self::REASON = "the resource sort moved its target"

          # The text of the work log line: the file, the old link, the new link and the reason.
          def text = "#{rel}: link #{change}; #{self.class::REASON}"

          def line = "amended #{dir}/#{text}"

          def preview = "preview: would amend #{dir}/#{text}"

          # Writes the `amended` line on the work log of the intent through `work`, the work graph.
          def write(work) = work.amend_intent(intent_id, text, path: rel, body:)
        end
      end
    end
  end
end
