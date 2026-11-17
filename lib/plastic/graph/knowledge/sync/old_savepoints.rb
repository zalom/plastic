# frozen_string_literal: true

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The savepoint.md files an older release printed. A sync down removes each one that
        # still holds the bytes that release printed, and names each one a person changed.
        class OldSavepoints
          FILE = "savepoint.md"

          attr_reader :removable, :kept

          def self.none = new([], [])

          def self.find(folder, retrieval)
            printed = retrieval.printed
            files = folder.intent_dirs.map { |dir| "#{dir}/#{FILE}" }.select { |rel| folder.exist?(rel) }
            removable, kept = files.partition { |rel| printed[rel] && printed[rel] == folder.digest(rel) }
            new(removable, kept)
          end

          def initialize(removable, kept)
            @removable = removable
            @kept = kept
          end

          def kept_lines = kept.map { |rel| "kept #{rel}: changed by hand; plastic sync up reads it into work.log" }

          def remove(folder)
            removable.map do |rel|
              folder.delete(rel)
              "removed #{rel}: work.log holds its lines"
            end
          end
        end
      end
    end
  end
end
