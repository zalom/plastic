# frozen_string_literal: true

require_relative "../command"
require_relative "../table"

# `plastic intent` - the list of `plastic intent ...` subcommands, straight out
# of the table; a word that names none of them is a usage error naming the
# same list, so a typo never falls through to a script.
module Plastic
  class CLI
    module Commands
      class Intent < Command
        USAGE_LINE = "plastic intent SUBCOMMAND [options]"

        def call
          unless arguments.empty?
            raise Usage, "no subcommand named #{arguments.first.inspect}. Try: #{subcommand_names.join(", ")}"
          end

          @output.row("usage", USAGE_LINE)
          subcommands.each { |name, (_file, _const, summary)| @output.row(name, summary) }
          @output.next_step("plastic intent show ID", because: "an id is the one thing every other subcommand needs")
        end

        private

        def subcommands
          TABLE.select { |name, _| name.start_with?("intent ") }.sort.to_h
        end

        def subcommand_names
          subcommands.keys
        end
      end
    end
  end
end
