# frozen_string_literal: true

require_relative "../backup"
require_relative "../../routine"
require_relative "../../cli/backup_store"

module Plastic
  module Commands
    class Backup
      # Lists the backups of one registered store, flagging a missing or changed file.
      class List < Routine
        include CLI::BackupStore

        reads :work
        takes_no_daily_backup

        workflow :code_backup_list, next: :noop
      end
    end
  end
end
