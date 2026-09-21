# frozen_string_literal: true

require_relative "subcommand_list"

# `plastic session` - the list of `plastic session ...` subcommands, straight
# out of the table.
module Plastic
  class CLI
    module Commands
      class Session < SubcommandList
        USAGE_LINE = "plastic session SUBCOMMAND [options]"
        PREFIX = "session"
        NEXT = 'plastic session commit "SUMMARY"'
        BECAUSE = "a commit is the smallest unit every other session subcommand builds on"
      end
    end
  end
end
