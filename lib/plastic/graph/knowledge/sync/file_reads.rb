# frozen_string_literal: true

require_relative "../reader"
require_relative "../../prints"
require_relative "../../schema"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # Reads files into rows, one transaction per database, then prints
        # each back from its rows, so the file holds the form the rows print.
        class FileReads
          def initialize(folder:, retrieval:, databases:, printer:)
            @folder = folder
            @retrieval = retrieval
            @databases = databases
            @printer = printer
          end

          # One line for each path read. A path the database refuses is left as it is and gets no line.
          def call(paths)
            reads = paths.map(&reader.method(:read))
            written = write(reads)
            done = reads.select { |read| written.include?(read) }
            reprint(done)
            done.map(&:line)
          end

          private

          # The intents of the rows. store/index.json is never read for them: the folders are.
          def reader = Reader.of_databases(@folder, @retrieval, @databases)

          # The work graph first, so a new intent's row is in place before its files.
          def write(reads)
            groups = reads.group_by(&:database).sort_by { |key, _group| Schema.store.index(key) }
            groups.flat_map { |key, group| apply_group(key, group) }
          end

          # The group commits together; when the database refuses it, each read gets its own transaction.
          def apply_group(key, group)
            commit(key, group)
            group
          rescue Database::Error
            group.select { |read| commit_alone(key, read) }
          end

          def commit_alone(key, read)
            commit(key, [read])
            true
          rescue Database::Error
            false
          end

          def commit(key, group)
            applies = group.map(&:apply)
            @databases.fetch(key).transaction { |batch| batch.apply(applies) }
          end

          def reprint(reads)
            fresh = Prints.of_store(@retrieval).to_h { |print| [print.path, print] }
            @printer.print(reads.map { |found| fresh[found.path] || found.kept_print(@folder) })
          end
        end
      end
    end
  end
end
