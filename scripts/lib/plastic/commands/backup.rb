# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Packs home.db and every store's three databases into one archive.
    class Backup < Routine
      workflow :code_backup, next: :noop
    end
  end
end
