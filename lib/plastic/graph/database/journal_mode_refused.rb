# frozen_string_literal: true

module Plastic
  module Graph
    class Database
      # A store file is in a journal mode other than delete, so one transaction would not be atomic over all three files.
      class JournalModeRefused < Error; end
    end
  end
end
