# frozen_string_literal: true

require_relative "subcommand_list"

# `plastic roadmap` - the list of `plastic roadmap ...` subcommands, straight
# out of the table; a word that names none of them is a usage error naming
# the same list, so a typo never falls through to a script.
module Plastic
  class CLI
    module Commands
      class Roadmap < SubcommandList
        USAGE_LINE = "plastic roadmap SUBCOMMAND [options]"
        PREFIX = "roadmap"
        NEXT = "plastic roadmap next"
        BECAUSE = "next names the roadmap most worth continuing, with no slug to guess"
      end
    end
  end
end
