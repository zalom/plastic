# frozen_string_literal: true

require_relative "../../../invalid"
require_relative "index/entry"
require_relative "index/link"
require_relative "index/parsed"
require_relative "index/reading"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Reads the INDEX.md of a store written before store/index.json. Each
        # status section gives its intents a status; a line may add a closing
        # date and a disposition. A Clusters section names clusters, and an
        # intent listed only there takes the status its marker gives. The
        # import reads it once and deletes it.
        module Index
          SECTIONS = { "Open" => "open", "Active" => "in_progress", "Parked" => "parked", "Future" => "future",
                       "Completed" => "done", "Done" => "done", "Abandoned" => "abandoned" }.freeze
          QUIET = %w[Clusters Relocated].freeze
          HEADING = /\A(?<level>###?) (?<name>.+)\z/

          module_function

          def parse(text) = Reading.new(links(text)).parsed

          def links(text)
            headings = {}
            text.each_line(chomp: true).filter_map { |line| link(line, headings) }
          end

          def link(line, headings)
            heading = line.match(HEADING)
            headings[heading[:level]] = heading[:name].strip if heading
            found = line.match(Link::PATTERN)
            Link.new(headings["##"], headings["###"], found) if found
          end
        end
      end
    end
  end
end
