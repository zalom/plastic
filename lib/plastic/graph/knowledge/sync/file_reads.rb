# frozen_string_literal: true

require_relative "../reader"
require_relative "../prints"
require_relative "../../schema"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # Reads files into rows, one transaction, then prints
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
            reads = reads_of(paths)
            written = write(reads)
            done = reads.select { |read| written.include?(read) }
            reprint(done)
            done.map(&:line).uniq
          end

          def read_all(paths)
            reads = reads_of(paths)
            commit(reads)
            reads
          rescue Database::Error, Invalid => error
            raise Failed, "cannot read #{paths.join(", ")}: #{error.message}"
          end

          def reprint(reads)
            fresh = [*Prints.of_store(@retrieval), *Prints.parts(@retrieval)].to_h { |print| [print.path, print] }
            @printer.print(reads.map { |found| found.printed(fresh, @folder) })
          end

          private

          # The reads of one call share one reader, so they hold one copy of the intent rows, whatever the count of paths.
          # The intents come from the rows; store/index.json is never read for them.
          def reads_of(paths)
            now = Plastic.timestamp(@retrieval.clock.now)
            reader = Reader.of(@folder, @retrieval)
            paths.map { |path| reader.read(path, now) }
          end

          # The reads commit together; when the reader or the database refuses them, each read gets its own transaction.
          def write(reads)
            commit(reads)
            reads
          rescue Database::Error, Invalid
            reads.select { |read| commit_alone(read) }
          end

          def commit_alone(read)
            commit([read])
            true
          rescue Database::Error, Invalid
            false
          end

          def commit(reads)
            applies = reads.map(&:apply)
            @databases.fetch(:store).transaction { |batch| batch.apply(applies) }
          end
        end
      end
    end
  end
end
