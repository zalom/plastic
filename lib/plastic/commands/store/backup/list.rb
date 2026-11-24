# frozen_string_literal: true

require_relative "../backup"
require_relative "../../../routine"
require_relative "../../../cli/one_store"

module Plastic
  module Commands
    module Store
      class Backup
        # Lists the backups of one registered store, flagging a missing or changed file.
        class List < Routine
          include CLI::OneStore

          reads :work
          skips_daily_backup

          workflow :code_backup_list, next: :noop
        end
      end
    end
  end
end
