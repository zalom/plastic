# frozen_string_literal: true

require_relative "../command"

# `plastic project list` - every store this machine holds, global and
# project, straight from Scope#stores, in this process.
module Plastic
  class CLI
    module Commands
      class ProjectList < Command
        USAGE_LINE = "plastic project list [--json]"

        def call
          scope.stores.each { |store| @output.row(store[:slug], store[:root]) }
          @output.next_step("plastic status", because: "status shows what is active in each store this just listed")
        end
      end
    end
  end
end
