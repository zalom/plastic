# frozen_string_literal: true

require_relative "sections"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        module Parse
          # The scan of a roadmap file, one line at a time, so `call` stays a plain loop.
          class Scan
            TITLE = /\A#\s+(?:Roadmap:\s*)?(.*)\z/
            TOP_HEADING = /\A##\s+(.+?)\s*\z/

            def initialize(path)
              @sections = Sections.new(path)
              @section = Sections::Ignored
              @title = nil
            end

            def line(text, number)
              @title ||= text[TITLE, 1]&.strip
              heading = text[TOP_HEADING, 1]
              heading ? enter(heading) : @section.line(text, number)
            end

            def finish = @section.finish

            def result = @sections.result(@title)

            private

            def enter(heading)
              @section.finish
              @section = @sections.named(heading)
            end
          end
        end
      end
    end
  end
end
