# frozen_string_literal: true

require "json"
require_relative "../../prints"
require_relative "../store_folder"
require_relative "../store_path"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # One path of a store folder, seen three ways: the hash of the file on
        # disk, the hash recorded when it was last printed, and the hash of the
        # print its rows give now. Each hash is nil when there is none.
        # `printed_by` names the other home that printed an index, nil for any other file.
        Entry = Data.define(:path, :file_sha, :printed_sha, :print, :printed_by) do
          def initialize(printed_by: nil, **hashes) = super
        end

        # What a sync does with one path.
        class Entry
          # What a sync in a direction does with the path.
          module Decision
            # :record a level file's hash, :read the file into rows, :print the rows into the
            # file, stop on a :conflict, or :none. A missing file is never a
            # change on the file side. An index another home printed prints from the rows
            # when this home holds no print of the index, and is read when it does.
            def action(direction)
              return :print if reprinted?
              return (printed_sha == file_sha) ? :none : :record if level?
              return :conflict if conflict?

              send(direction)
            end

            # The index prints from the rows when another home printed it and this home holds no print of it. An index
            # that a person changed and that has rows is read into rows. When it cannot be read, it is kept as written
            # if this home holds a print of it, and printed from the rows if not. Any other index is left as it is.
            def generated_up(unreadable_files)
              return :print if reprinted?
              return :none unless hand_edited? && rows_sha
              return :read unless unreadable_files.key?(path)

              printed_sha ? :none : :print
            end

            private

            def up = file_changed? ? :read : :none

            def down = (rows_changed? || (rows_sha && !file_sha)) ? :print : :none
          end

          include Decision

          # The print of a path with no rows.
          NO_PRINT = Prints::Print.new(nil, nil, nil)

          # A file printed from rows: the index, a context view or a roadmap.
          def self.generated?(path) = path == StoreFolder::INDEX || StorePath.context_view?(path) || StorePath.roadmap?(path)

          # The entry of `path` in `folder`. A generated file that holds the content of its
          # print in other bytes is level: the bytes are a formatter's, not a person's edit.
          # The index that another home printed, when this home holds no print of it, is no edit: the rows print it again.
          def self.for(folder, path, printed_sha, print)
            file_sha = level_sha(folder, path, print)
            new(path, file_sha, printed_of(path, printed_sha, file_sha, print), print, other_origin(folder, path, print))
          end

          # A part of the index, the clusters or the links, with no record of a print count as printed when the rows hold what the file does not.
          def self.printed_of(path, printed_sha, file_sha, print)
            unrecorded = Prints::Parts.path?(path) && printed_sha.nil?
            (unrecorded && print.other_than?(file_sha)) ? print.sha256 : printed_sha
          end

          # The origin of the other home that printed the index, nil when this home printed it or the folder holds none.
          def self.other_origin(folder, path, print)
            return unless path == StoreFolder::INDEX && folder.exist?(path)

            text = print.text
            return unless text

            theirs = origin_of(folder.read(path))
            theirs unless theirs == origin_of(text)
          end

          # The top-level origin of an index, nil when the text is no JSON object.
          def self.origin_of(text)
            index = JSON.parse(text.dup.force_encoding(Encoding::UTF_8))
            index["origin_id"] if index.is_a?(Hash)
          rescue JSON::ParserError
            nil
          end

          def self.level_sha(folder, path, print)
            sha = Prints::Parts.path?(path) ? part_digest(folder, path) : folder.digest(path)
            rows = print.sha256
            (sha && generated?(path) && rows && same_content?(folder.read(path), print.text)) ? rows : sha
          end

          def self.part_digest(folder, path) = folder.exist?(StoreFolder::INDEX) ? Prints::Parts.file_digest(path, folder.read(StoreFolder::INDEX)) : nil

          def self.same_content?(bytes, text)
            JSON.parse(bytes.force_encoding(Encoding::UTF_8)) == JSON.parse(text)
          rescue JSON::ParserError
            false
          end

          def rows_sha = print.sha256

          # An index another home printed, on a home that holds no print of the index: the rows print it again.
          def reprinted? = !printed_by.nil? && printed_sha.nil?

          # The index: the rows print it again after a read. A roadmap and a context view are read like any file.
          def generated? = path == StoreFolder::INDEX

          # The file already holds what the rows print.
          def level? = !file_sha.nil? && file_sha == rows_sha

          def file_changed? = file_sha && file_sha != printed_sha

          # A person changed a file since its last print, or one never printed: the file holds
          # neither the rows' print nor the recorded one. A graph file against bare rows is not an edit.
          def hand_edited? = !reprinted? && !level? && file_changed? && !bare_graph?

          def rows_changed? = rows_sha && rows_sha != printed_sha && !bare_graph?

          def bare_graph? = !printed_sha && StorePath.graph_file?(path) && rows_sha == Prints.empty_graph_sha(path)

          def conflict? = !level? && file_changed? && rows_changed?

          # The rows print something and the file does not hold it yet.
          def reprintable? = !rows_sha.nil? && !level?

          # A changed file of an intent that has its rows, or an index a person changed after its print; the files of a folder without rows read after its row is written.
          def readable_by_up?(rowed)
            return path == StoreFolder::INDEX && hand_edited? && !rows_sha.nil? if generated?

            %i[read conflict].include?(action(:up)) && readable_path?(rowed)
          end

          private

          def readable_path?(rowed) = StorePath.roadmap?(path) || Prints::Parts.path?(path) || rowed.any? { |dir| path.start_with?("#{dir}/") }
        end
      end
    end
  end
end
