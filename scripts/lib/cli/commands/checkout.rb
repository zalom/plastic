# frozen_string_literal: true

require_relative "../command"
require_relative "../../store_sync"

module Plastic
  class CLI
    module Commands
      class Checkout < Command
        USAGE_LINE = "plastic checkout [--json]"

        def call
          home = scope.plastic_home
          raise Failure, "no databases at #{home}; run plastic sync" unless File.exist?(ReferenceArchive.path(home))

          restored = StoreSync.checkout(home)
          @output.row("restored", restored.empty? ? "nothing was missing" : restored)
          @output.next_step("plastic sync --dry-run", because: "checkout restores missing files only; a changed file is never overwritten")
        rescue Sqlite::Error => e
          raise Failure, e.message
        end
      end
    end
  end
end
