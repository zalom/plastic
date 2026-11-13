# frozen_string_literal: true

require_relative "entry"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        module Parse
          # The "## Log" section: dated lines, where an indented line continues the one above.
          class Log
            LEAD = /\A-\s+(\d{4}-\d{2}-\d{2})\s+(.*)\z/

            attr_reader :list

            def initialize(problems)
              @problems = problems
              @list = []
              @entry = nil
            end

            def line(text, number)
              stripped = text.strip
              if text.start_with?("- ")
                start(stripped, number)
              elsif stripped.empty?
                finish
              elsif @entry
                @entry.add(stripped)
              end
            end

            def finish
              return unless @entry

              read(@entry.text, @entry.number)
              @entry = nil
            end

            private

            def start(stripped, number)
              finish
              @entry = Entry.new(stripped, number)
            end

            def read(joined, number)
              match = LEAD.match(joined)
              return @problems.add("cannot read log line #{joined.inspect}", number) unless match

              @list << LogLine.new(at: match[1], text: match[2].strip)
            end
          end
        end
      end
    end
  end
end
