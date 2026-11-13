# frozen_string_literal: true

require "json"
require_relative "../../../invalid"
require_relative "../store_folder"
require_relative "../reader/graph_file"
require_relative "index"
require_relative "roadmaps"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # Finds every problem of a legacy store before anything is written, and
        # raises one error that names them all.
        class Check
          GRAPH = %r{\Astore/[^/]+/graph\.json\z}
          STATUSES = Index::SECTIONS.values.uniq.freeze

          def initialize(folder)
            @folder = folder
          end

          def call
            problems = unreadable + roadmap_problems + index_problems + graph_problems
            raise Invalid, problems.join("; ") if problems.any?
          end

          private

          def unreadable = paths.reject { |path| File.readable?(@folder.path(path)) }.map { |path| "#{path} cannot be read" }

          def paths = [StoreFolder::LEGACY_INDEX, *@folder.intent_files, *roadmap_paths.map { |path| roadmaps.relative(@folder.root, path) }].select { |path| @folder.exist?(path) }

          def roadmaps = (@roadmaps ||= Roadmaps.new)

          def roadmap_paths = roadmaps.roadmap_files(@folder.root)

          def roadmap_problems
            return [] unless unreadable.empty?

            roadmaps.parse(@folder.root).values.flat_map(&:problems)
          end

          def index_problems
            return [] unless @folder.exist?(StoreFolder::LEGACY_INDEX)

            parsed = Index.parse(@folder.read(StoreFolder::LEGACY_INDEX).force_encoding(Encoding::UTF_8))
            listed = parsed.entries.map(&:dir)
            dirs = @folder.intent_dirs
            Index::Parsed.missing_folders(listed - dirs) + (dirs - listed).filter_map { |dir| unlisted_problem(dir) }
          rescue Invalid => error
            [error.message]
          rescue SystemCallError
            []
          end

          def unlisted_problem(dir)
            status = @folder.front_matter(dir)["status"]
            "#{dir} has no entry in INDEX.md" unless STATUSES.include?(status)
          end

          def graph_problems
            @folder.intent_files.grep(GRAPH).flat_map { |path| graph_file_problems(path) }
          end

          def graph_file_problems(path)
            intent_id = File.basename(File.dirname(path)).split("--", 2).first
            Reader::GraphFile.new(@folder.read(path), intent_id, nil, path).problems
          rescue SystemCallError
            []
          end
        end
      end
    end
  end
end
