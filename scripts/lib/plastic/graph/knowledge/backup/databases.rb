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
            return if text.nil?

            names = text.split(",").map(&:strip).uniq
            unknown = names - all
            raise Unknown, "unknown database #{unknown.first.inspect}; the databases are #{all.sort.join(", ")}" if names.empty? || unknown.any?

            names
          end

          def self.goal(names) = names.nil? || names.sort == all.sort ? "full" : "partial:#{names.map { |name| "#{name}.db" }.join(",")}"
        end
      end
    end
  end
end
