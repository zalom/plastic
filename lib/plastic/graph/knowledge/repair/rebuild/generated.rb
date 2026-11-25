# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Repair
        module Rebuild
          # Tells whether an old file holds no data: an empty file, a placeholder a template wrote, or a stub that an
          # older end-intent backfilled from the record.
          module Generated
            PLACEHOLDER = "<!-- plastic:placeholder -->"
            STUB = "backfilled from the record by end-intent"
            HEAD = 3
            # The lines a template writes: blanks, comments, headings, an empty table, and the unfilled items.
            TEMPLATE = /\A(?:|<!--.*|\#.*|\|[-\s|:]*|\|\s*Date\b.*|\{\{.*|\(move items.*|\(implementation notes.*|(?:- \[ \] |\d+\. )?(?:Step \d+ — )?\.\.\.)\z/

            # A generator writes its marker in the first lines; the same words quoted further down are text. A file that
            # keeps the placeholder marker but holds a line the template does not write was filled in, and is data.
            def self.call(text)
              head = text.lines.first(HEAD).join
              text.strip.empty? || head.include?(STUB) || (head.include?(PLACEHOLDER) && text.lines.all? { |line| line.strip.match?(TEMPLATE) })
            end
          end
        end
      end
    end
  end
end
