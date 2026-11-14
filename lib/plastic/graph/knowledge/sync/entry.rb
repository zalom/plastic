# frozen_string_literal: true

require "json"
require_relative "../../prints"
require_relative "../store_folder"

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

          def self.generated?(path) = StoreFolder.context_view?(path) || path == StoreFolder::INDEX || roadmap?(path)

          # No reader turns a roadmap file into rows, so sync up prints it again from its rows.
          def self.roadmap?(path) = StoreFolder.roadmap?(path)

          # The entry of `path` in `folder`. A generated file that holds the content of its
          # print in other bytes is level: the bytes are a formatter's, not a person's edit.
          def self.for(folder, path, printed_sha, print)
            new(path, level_sha(folder, path, print), printed_sha, print)
          end

          def self.level_sha(folder, path, print)
            sha = folder.digest(path)
            rows = print.sha256
            (sha && generated?(path) && rows && same_content?(folder.read(path), print.text)) ? rows : sha
          end

          def self.same_content?(bytes, text)
            JSON.parse(bytes.force_encoding(Encoding::UTF_8)) == JSON.parse(text)
          rescue JSON::ParserError
            false
          end

          def rows_sha = print.sha256

          # The index and the context views: the rows print them again after a read.
          def generated? = Entry.generated?(path)

          # The file already holds what the rows print.
          def level? = !file_sha.nil? && file_sha == rows_sha

          def file_changed? = file_sha && file_sha != printed_sha

          # A person changed a file since its last print, or one never printed: the file holds
          # neither the rows' print nor the recorded one. A graph file against bare rows is not an edit.
          def hand_edited? = !level? && file_changed? && !bare_graph?

          def rows_changed? = rows_sha && rows_sha != printed_sha && !bare_graph?

          def bare_graph? = !printed_sha && StoreFolder.graph_file?(path) && rows_sha == Prints.empty_graph_sha(path)

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
end
