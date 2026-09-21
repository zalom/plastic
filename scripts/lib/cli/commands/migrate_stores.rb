# frozen_string_literal: true

require_relative "../command"
require_relative "../../stores_move"

module Plastic
  class CLI
    module Commands
      class MigrateStores < Command
        USAGE_LINE = "plastic migrate stores [--dry-run] [--json]"

        def call
          move = StoresMove.new(scope.plastic_home, qmd_index: File.join(@home, ".config", "qmd", "index.yml"), dry_run: options[:dry_run])
          move.call.each { |verb, text| @output.row(verb, text) }
          return @output.next_step("plastic migrate stores", because: "the dry run changed nothing") if options[:dry_run]

          @output.row("remove", "rm -rf #{move.copy}")
          @output.next_step("plastic doctor", because: "it checks the moved stores, and the copy stays until you remove it")
        rescue StoresMove::Refused => e
          raise Refusal, e.message
        end

        private

        def switches(parser)
          parser.on("--dry-run") { options[:dry_run] = true }
        end
      end
    end
  end
end
