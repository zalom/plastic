# frozen_string_literal: true

require_relative "../prints"

module Plastic
  module Graph
    class Sync
      # One path of a store folder, seen three ways: the hash of the file on
      # disk, the hash recorded when it was last printed, and the hash of the
      # print its rows give now. Each hash is nil when there is none.
      Entry = Data.define(:path, :file_sha, :printed_sha, :print)

      # What a sync does with one path.
      class Entry
        # The print of a path with no rows.
        NO_PRINT = Prints::Print.new(nil, nil, nil, nil)

        def rows_sha = print.sha256

        # The file already holds what the rows print.
        def level? = file_sha && file_sha == rows_sha

        def file_changed? = file_sha && file_sha != printed_sha

        def rows_changed? = rows_sha && rows_sha != printed_sha

        def conflict? = !level? && file_changed? && rows_changed?

        # What a sync in `direction` does with this path: :record a level
        # file's hash, :read the file into rows, :print the rows into the
        # file, stop on a :conflict, or :none. A missing file is never a
        # change on the file side.
        def action(direction)
          return (printed_sha == file_sha) ? :none : :record if level?
          return :conflict if conflict?

          send(direction)
        end

        private

        def up = file_changed? ? :read : :none

        def down = (rows_changed? || (rows_sha && !file_sha)) ? :print : :none
      end
    end
  end
end
