# frozen_string_literal: true

require_relative "subcommand_list"

module Plastic
  class CLI
    module Commands
      class Migrate < SubcommandList
        USAGE_LINE = "plastic migrate SUBCOMMAND [options]"
        PREFIX = "migrate"
        NEXT = "plastic migrate stores --dry-run"
        BECAUSE = "a dry run prints every move and rewrite and changes nothing"
      end
    end
  end
end
