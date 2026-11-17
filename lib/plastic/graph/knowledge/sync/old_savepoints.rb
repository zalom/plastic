# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The savepoint.md files an older release printed. A sync down removes each one that
        # still holds the bytes that release printed, and names each one a person changed.
        class OldSavepoints
          FILE = "savepoint.md"
          REASONS = { edited: "changed by hand; plastic sync up reads it into work.log", unprinted: "never printed by this home" }.freeze

          attr_reader :removable, :kept

          def self.none = new([], {})

          def self.find(folder, retrieval)
            printed = retrieval.printed
            files = folder.intent_dirs.map { |dir| "#{dir}/#{FILE}" }.select { |rel| folder.exist?(rel) }
            removable, kept = files.partition { |rel| printed[rel] && printed[rel] == folder.digest(rel) }
            new(removable, kept.to_h { |rel| [rel, reason(printed, rel)] })
          end

          def self.reason(printed, rel) = REASONS.fetch(printed[rel] ? :edited : :unprinted)

          def initialize(removable, kept)
            @removable = removable
            @kept = kept
          end

          def kept_lines = kept.map { |rel, reason| "kept #{rel}: #{reason}" }

          def remove(folder, databases)
            removable.map do |rel|
              folder.delete(rel)
              forget(databases, rel)
              "removed #{rel}: work.log holds its lines"
            end
          end

          private

          def forget(databases, rel) = Graph::Schema.store.each { |key| databases.fetch(key).transaction { |batch| batch.remove(:printed, path: rel) } }
        end
      end
    end
  end
end
