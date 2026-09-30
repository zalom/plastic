# frozen_string_literal: true

require "json"
require_relative "../invalid"
require_relative "intent"
require_relative "printer"
require_relative "prints"
require_relative "reader"
require_relative "schema"
require_relative "store_folder"
require_relative "sync/plan"
require_relative "sync/legacy_import"

module Plastic
  module Graph
    # Levels a store folder and its rows in one direction. Sync up reads the
    # files people changed into rows; sync down prints the rows that changed
    # into files. A record changed on both sides since the last print is a
    # conflict, and only an overwrite settles it.
    class Sync
      def initialize(folder:, retrieval:, databases:)
        @folder = folder
        @retrieval = retrieval
        @databases = databases
      end

      def plan(direction, overwrite: false, merge: false)
        Plan.build(@folder, @retrieval, direction:, overwrite:, merge:)
      end

      # Applies every action of `plan` but the conflicts, and says what it did, one line per file.
      def apply(plan)
        @folder.ignore_databases
        return LegacyImport.new(self, @folder, @retrieval, @databases).call if plan.legacy

        printer.record(plan.taking(:record).map(&:print))
        (plan.direction == :up) ? read(plan.taking(:read).map(&:path)) : print(plan.taking(:print).map(&:print))
      end

      # Reads files into rows, one transaction per database, then prints
      # each back from its rows, so the file holds the form the rows print.
      def read(paths)
        reader = Reader.new(@folder, known_intents, @retrieval.origin_id)
        reads = paths.map { |path| reader.read(path) }
        write_reads(reads)
        reprint(reads)
        paths.map { |path| "read #{path}" }
      end

      def print(prints) = printer.print(prints).map { |path| "printed #{path}" }

      def printer = (@printer ||= Printer.new(@folder, @databases, @retrieval))

      private

      # The work graph first, so a new intent's row is in place before its files.
      def write_reads(reads)
        reads.group_by(&:database).sort_by { |key, _group| Schema::STORE.index(key) }.each do |key, group|
          @databases.fetch(key).transaction { |batch| group.each { |found| found.apply.call(batch) } }
        end
      end

      def reprint(reads)
        fresh = Prints.of_store(@retrieval).to_h { |print| [print.path, print] }
        printer.print(reads.map { |found| fresh[found.path] || kept_as_is(found) })
      end

      # A file whose rows print nothing, such as an empty savepoint.md, keeps its own hash.
      def kept_as_is(found) = Prints::Print.new(found.path, found.database, @folder.sha256(found.path), nil)

      # The intents of the rows, and those a hand edit of store/index.json adds or changes.
      def known_intents
        rows = @retrieval.intents.to_h { |intent| [intent.intent_id, intent] }
        rows.merge(index_intents.to_h { |intent| [intent.intent_id, intent] })
      end

      def index_intents
        return [] unless @folder.exist?(StoreFolder::INDEX)

        Array(JSON.parse(@folder.read(StoreFolder::INDEX))["intents"]).map { |entry| Intent.from_h(entry) }
      rescue JSON::ParserError => error
        raise Invalid, "#{StoreFolder::INDEX} does not parse: #{error.message.lines.first.strip}"
      end
    end
  end
end
