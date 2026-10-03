# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Packs home.db and every store's three databases into one archive.
    class Backup < Routine
      option :dry_run, switch: "--dry-run", default: false, text: "preview the backup without writing an archive"

      workflow :code_preview_backup do
        on :done, next: :noop
        on :continue, next: :code_backup
      end
      workflow :code_backup, next: :noop

      private

      def keeps_routine_run? = !parsed[:dry_run]
    end
  end
end
