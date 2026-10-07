# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Intent
        class Revision
          # The lead of a section: the lines under its heading, up to the next heading.
          module Section
            HEADING = /\A##?#? /

            module_function

            def lead(start, lines) = lines.drop(start + 1).take_while { |text| !text.match?(HEADING) }

            # The lead's blank lines kept around the new text; an empty lead gets one blank line each side.
            def filled(old, text)
              return ["", text, ""] if old.all?(&:empty?)

              before = old.take_while(&:empty?)
              after = old.reverse.take_while(&:empty?)
              before + [text] + after
            end
          end
        end
      end
    end
  end
end
