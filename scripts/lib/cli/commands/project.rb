# frozen_string_literal: true

require_relative "subcommand_list"

# `plastic project` - the list of `plastic project ...` subcommands, straight
# out of the table; a word that names none of them is a usage error naming
# the same list, so a typo never falls through to a script.
module Plastic
  class CLI
    module Commands
      class Project < SubcommandList
        USAGE_LINE = "plastic project SUBCOMMAND [options]"
        PREFIX = "project"
        NEXT = "plastic project list"
        BECAUSE = "the stores it lists are what every other subcommand names a slug from"
      end
    end
  end
end
