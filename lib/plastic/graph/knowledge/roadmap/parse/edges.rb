# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        module Parse
          # The "## Graph" section: one "needs" line for each item that waits on others.
          class Edges
            LEAD = /\A-\s*(\S+)\s+needs\b(.*)\z/

            # The targets of one "needs" line, or the reason they cannot be read.
            class Targets
              ROOT = "nothing"

              def initialize(text, line)
                @line = line
                @list = text.to_s.strip.split(/[,\s]+/)
              end

              def list = (@list == [ROOT]) ? [] : @list

              def problem = empty_problem || mixed_problem || bad_problem

              private

              def empty_problem = ("malformed graph line, no target: #{@line.inspect}" if @list.empty?)

              def mixed_problem
                "root target mixed with a real target: #{@line.inspect}" if @list.include?(ROOT) && @list.length > 1
              end

              def bad_problem
                bad = @list.find { |target| target != ROOT && !TOKEN.match?(target) }
                "not a plain id #{bad.inspect} on graph line: #{@line.inspect}" if bad
              end
            end

            attr_reader :list

            def initialize(problems)
              @problems = problems
              @list = {}
            end

            def line(text, number)
              stripped = text.strip
              match = LEAD.match(stripped)
              read(match, stripped, number) if match
            end

            def finish = nil

            private

            def read(match, stripped, number)
              targets = Targets.new(match[2], stripped)
              problem = targets.problem
              problem ? @problems.add(problem, number) : @list[match[1]] = targets.list
            end
          end
        end
      end
    end
  end
end
