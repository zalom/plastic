# frozen_string_literal: true

require_relative "../backup"
require_relative "../../routine"
require_relative "../backup_store"

module Plastic
  module Commands
    class Backup
      # Lists the backups of one registered store, flagging a missing or changed file.
      class List < Routine
        include BackupStore

        reads :work

        workflow :code_backup_list, next: :noop
      end
    end
  end
end
