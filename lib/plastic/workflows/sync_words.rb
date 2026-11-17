# frozen_string_literal: true

module Plastic
  module Workflows
    # The words a sync says about its direction, its failures and the files it cannot read.
    module SyncWords
      NAMES = { up: "the rows hold every file changed by hand", down: "the files hold every row that changed" }.freeze
      PLAN_FAILURES = {
        up: "an overwrite path names no file and no rows",
        down: "a sync down finds the old index file of the store and needs plastic sync up first, or an overwrite path names no file and no rows"
      }.freeze

      UNREADABLE = "intent folders that could not be read, the others were read:\n%{unreadable}\n" \
                   "fix or remove each folder named, then run plastic sync up again"

      UNREADABLE_FILES = "files that cannot be read into rows, the others were read:\n%{unreadable_files}"
      REPRINTED_ELSEWHERE = "the home that holds the rows prints the file again with plastic sync down, and the file is then copied here again"
    end
  end
end
