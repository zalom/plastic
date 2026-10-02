# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Lists every backup this machine has written, flagging a missing or changed file.
    class BackupList < Routine
      workflow :code_backup_list, next: :noop
    end
  end
end
