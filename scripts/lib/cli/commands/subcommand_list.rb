# frozen_string_literal: true

require_relative "../command"
require_relative "../table"

# Plastic::CLI::Commands::SubcommandList (intent 372, family 3) - the shared
# base every bare group command (`plastic intent`, `plastic project`,
# `plastic roadmap`) runs on: list the table rows under its prefix, or a
# usage error naming that same list for a word that matches none of them.
module Plastic
  class CLI
    module Commands
      class SubcommandList < Command
        def call
          unless arguments.empty?
            raise Usage, "no subcommand named #{arguments.first.inspect}. Try: #{subcommand_names.join(", ")}"
          end

          @output.row("usage", self.class::USAGE_LINE)
          subcommands.each { |name, (_file, _const, summary)| @output.row(name, summary) }
          @output.next_step(self.class::NEXT, because: self.class::BECAUSE)
        end

        private

        def subcommands
          TABLE.select { |name, _| name.start_with?("#{self.class::PREFIX} ") }.sort.to_h
        end

        def subcommand_names
          subcommands.keys
        end
      end
    end
  end
end
