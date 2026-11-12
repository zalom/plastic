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

          # One line for each path read.
          def call(paths)
            reads = paths.map(&reader.method(:read))
            write(reads)
            reprint(reads)
            reads.map(&:line)
          end

          private

          # The intents of the rows. store/index.json is never read for them: the folders are.
          def reader
            known = @retrieval.intents.to_h { |intent| [intent.intent_id, intent] }
            Reader.new(@folder, known, @retrieval.origin_id, retrieval: @retrieval)
          end

          # The work graph first, so a new intent's row is in place before its files.
          def write(reads)
            reads.group_by(&:database).sort_by { |key, _group| Schema.store.index(key) }.each do |key, group|
              apply_group(key, group)
            end
          end

          def apply_group(key, group)
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
