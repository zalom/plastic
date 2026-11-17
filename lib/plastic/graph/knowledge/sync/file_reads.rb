# frozen_string_literal: true

require_relative "../reader"
require_relative "../../prints"
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
            now = Plastic.timestamp(@retrieval.clock.now)
            reads = paths.map { |path| reader.read(path, now) }
            written = write(reads)
            done = reads.select { |read| written.include?(read) }
            reprint(done)
            done.map(&:line).uniq
          end

          private

          # The intents of the rows. store/index.json is never read for them: the folders are.
          def reader = Reader.of(@folder, @retrieval)

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

          # A roadmap file read into rows is printed again from them, so the file holds the form the rows print.
          def roadmap_print(path)
            slug = path[%r{\Aroadmaps/(.+)\.md\z}, 1]
            Prints.roadmap(@retrieval, slug) if slug && @retrieval.roadmap(slug)
          end

          def reprint(reads)
            fresh = [*Prints.of_store(@retrieval), *Prints.parts(@retrieval)].to_h { |print| [print.path, print] }
            @printer.print(reads.map { |found| fresh[found.path] || roadmap_print(found.path) || found.kept_print(@folder) })
          end
        end
      end
    end
  end
end
