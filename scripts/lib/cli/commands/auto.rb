# frozen_string_literal: true

require_relative "subcommand_list"

# `plastic auto` - the list of `plastic auto ...` subcommands, straight out of
# the table.
module Plastic
  class CLI
    module Commands
      class Auto < SubcommandList
        USAGE_LINE = "plastic auto SUBCOMMAND [options]"
        PREFIX = "auto"
        NEXT = "plastic auto start ID"
        BECAUSE = "starting an intent is what every other auto subcommand needs first"
      end
    end
  end
end
