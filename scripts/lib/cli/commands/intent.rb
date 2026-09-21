# frozen_string_literal: true

require_relative "subcommand_list"

# `plastic intent` - the list of `plastic intent ...` subcommands, straight out
# of the table; a word that names none of them is a usage error naming the
# same list, so a typo never falls through to a script.
module Plastic
  class CLI
    module Commands
      class Intent < SubcommandList
        USAGE_LINE = "plastic intent SUBCOMMAND [options]"
        PREFIX = "intent"
        NEXT = "plastic intent show ID"
        BECAUSE = "an id is the one thing every other subcommand needs"
      end
    end
  end
end
