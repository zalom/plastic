# frozen_string_literal: true

require_relative "../../prints"
require_relative "../store_folder"
require_relative "changes"
require_relative "settling"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # One path of a store folder, seen three ways: the hash of the file on
        # disk, the hash recorded when it was last printed, and the hash of the
        # print its rows give now. Each hash is nil when there is none.
        Entry = Data.define(:path, :file_sha, :printed_sha, :print)

        # What a sync does with one path.
        class Entry
          # The print of a path with no rows.
          NO_PRINT = Prints::Print.new(nil, nil, nil, nil)

          include Settling
          include Changes

          def self.generated?(path) = path == StoreFolder::INDEX || reprinted?(path)

          # The generated files no reader turns into rows: the context views and the roadmaps.
          def self.reprinted?(path) = StoreFolder.context_view?(path) || roadmap?(path)

          # No reader turns a roadmap file into rows, so sync up prints it again from its rows.
          def self.roadmap?(path) = path.to_s.start_with?("roadmaps/")

          def rows_sha = print.sha256

          # The print from `fresh`, a hash of prints by path, when the rows have a newer one.
          def reprinted_from(fresh) = fresh.fetch(path, print)

          # The index and the context views: the rows print them again after a read.
          def generated? = Entry.generated?(path)

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
end
