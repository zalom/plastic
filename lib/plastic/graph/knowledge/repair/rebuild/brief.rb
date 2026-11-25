# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      module Repair
        module Rebuild
          # One file of an old actions/ folder: a worker brief, or a step evidence file. It names the step it served in
          # its file name, ACTION_N, and may hold a Result section.
          class Brief
            attr_reader :name, :text

            # A table whose columns include Evidence followed by Result, with any columns before them.
            EVIDENCE = /^\|(?:[^|\n]*\|)*\s*Evidence\s*\|\s*Result\s*\|/i

            def initialize(name, text)
              @name = File.basename(name)
              @text = text
            end

            def number = @name[/\AACTION[_ -]?(\w+?)(?:[_ -].*)?\.md\z/i, 1]

            def heading = @text[/^#\s+(.+)$/, 1]&.strip || File.basename(@name, ".*")

            def result
              lines = @text.lines(chomp: true)
              from = lines.index { |line| line.match?(/\A##+\s*Result\b/i) } or return
              body = lines.drop(from + 1).take_while { |line| !line.start_with?("#") }.join("\n").strip
              body unless body.empty?
            end

            def evidence? = @text.match?(EVIDENCE)
          end
        end
      end
    end
  end
end
