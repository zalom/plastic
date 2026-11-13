# frozen_string_literal: true

require_relative "../../../../invalid"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        module Index
          # One intent's membership of a named cluster.
          Member = Data.define(:name, :intent_id)

          # The entries and clusters of one file.
          Parsed = Data.define(:entries, :clusters)

          # What the import checks and reports.
          class Parsed
            def self.missing_entries(dirs) = dirs.map { |dir| "#{dir} has no entry in INDEX.md" }

            def self.missing_folders(dirs) = dirs.map { |dir| "#{dir} is in INDEX.md and has no folder" }

            # Every intent folder must have an entry and every entry a folder;
            # a guess would import a record nobody wrote.
            def check(dirs)
              listed = entries.map(&:dir)
              problems = Parsed.missing_entries(dirs - listed) + Parsed.missing_folders(listed - dirs)
              raise Invalid, problems.join("; ") if problems.any?

              self
            end

            def counts = { "intents" => entries.size, "clusters" => clusters.size }
          end
        end
      end
    end
  end
end
