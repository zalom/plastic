# frozen_string_literal: true

require_relative "../../../invalid"
require_relative "../front_matter"
require_relative "../intent"
require_relative "../store_folder"
require_relative "index"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # The problems the legacy INDEX.md of a store has: a line it cannot read, a folder it lists that is
        # missing, and a folder it does not list that gives no status.
        class IndexProblems
          STATUSES = Index::SECTIONS.values.uniq.freeze

          def initialize(folder)
            @folder = folder
          end

          def call
            return [] unless @folder.exist?(StoreFolder::LEGACY_INDEX)

            folder_problems(Index.parse(@folder.read(StoreFolder::LEGACY_INDEX).force_encoding(Encoding::UTF_8)))
          rescue Invalid => error
            [error.message]
          rescue SystemCallError
            []
          end

          private

          def folder_problems(parsed)
            listed = parsed.entries.map(&:dir)
            dirs = @folder.intent_dirs
            Index::Parsed.missing_folders(listed - dirs) + (dirs - listed).filter_map { |dir| unlisted_problem(dir) }
          end

          def unlisted_problem(dir)
            status = FrontMatter.new(@folder).read(dir)["status"]
            "#{dir} has no entry in INDEX.md" unless STATUSES.include?(Intent.stored_state(status))
          end
        end
      end
    end
  end
end
