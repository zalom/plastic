# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Imports every legacy store under the home: `--dry-run` against a
    # throwaway copy, `--apply` against the real one. Exactly one of the two
    # is required.
    class MigrateStores < Routine
      option :dry_run, switch: "--dry-run", text: "copy the stores and report, writing nothing real"
      option :apply, switch: "--apply", text: "import every legacy store under the real home"

      workflow :code_migrate_stores, next: :noop

      def call
        raise CLI::Command::Usage, "pass exactly one of --dry-run or --apply" if parsed[:dry_run] == parsed[:apply]

        super
      end
    end
  end
end
