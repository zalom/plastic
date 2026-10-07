# frozen_string_literal: true

require_relative "../backup"
require_relative "../../schema"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # The comma list of database names a backup or a restore takes. Every
        # call parses it here, so both commands read it alike.
        module Databases
          # A name that is not a store database.
          class Unknown < StandardError; end

          def self.all = Schema.store.map { |key| Schema.file(key).delete_suffix(".db") }

          # The names in the list, each once, or nil when no list was given.
          def self.parse(text)
            return unless text

            names = text.split(",").map(&:strip).uniq
            unknown = names - all
            raise Unknown, "unknown database #{unknown.first.inspect}; the databases are #{all.sort.join(", ")}" if names.empty? || unknown.any?

            names
          end

          # The names a call works on: those listed, or all of them.
          def self.chosen(names) = Array(names).then { |list| list.empty? ? all : list }

          def self.goal(names)
            listed = chosen(names)
            (listed.sort == all.sort) ? "full" : "partial:#{listed.map { |name| "#{name}.db" }.join(",")}"
          end
        end
      end
    end
  end
end
