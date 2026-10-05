# frozen_string_literal: true

require_relative "../routine"
require_relative "backup_store"

module Plastic
  module Commands
    # Lists the backups of one registered store, flagging a missing or changed file.
    class BackupList < Routine
      include BackupStore

      workflow :code_backup_list, next: :noop
    end
  end
end
