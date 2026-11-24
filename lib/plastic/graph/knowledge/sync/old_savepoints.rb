# frozen_string_literal: true

require_relative "../../../layout"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The savepoint.md files an older release printed. A sync down removes each one that
        # still holds the bytes that release printed, and names each one a person changed.
        class OldSavepoints
          FILE = Layout.legacy.find { |entry| entry.sync == "lines" }.name
          REASONS = { edited: "changed by hand; plastic store sync up reads it into work.log", unprinted: "never printed by this home" }.freeze

          attr_reader :removable, :kept

          def self.none = new([], {})

          def self.find(folder, retrieval)
            printed = retrieval.stored.printed
            files = folder.intent_dirs.map { |dir| "#{dir}/#{FILE}" }.select { |rel| folder.exist?(rel) }
            removable, kept = files.partition { |rel| printed[rel] == folder.digest(rel) }
            new(removable, kept.to_h { |rel| [rel, reason(printed, rel)] })
          end

          def self.reason(printed, rel) = REASONS.fetch(printed[rel] ? :edited : :unprinted)

          def initialize(removable, kept)
            @removable = removable
            @kept = kept
          end

          def kept_lines = kept.map { |rel, reason| "kept #{rel}: #{reason}" }

          def remove(folder, databases)
            removable.each { |rel| folder.delete(rel) }
            databases.fetch(:store).transaction { |batch| batch.remove_all(:printed, forgotten) }
            removable.map { |rel| "removed #{rel}: work.log holds its lines" }
          end

          private

          def forgotten = removable.map { |rel| { path: rel } }
        end
      end
    end
  end
end
