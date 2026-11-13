# frozen_string_literal: true

require "json"
require_relative "../../../invalid"
require_relative "../store_folder"
require_relative "../reader/graph_file"
require_relative "index_problems"
require_relative "roadmaps"

module Plastic
  module Graph
    module Knowledge
      module Legacy
        # The read-only checks that must pass before a legacy store is imported.
        class Check
          # The error that names every problem the checks found.
          Failed = Class.new(Invalid)

          GRAPH = %r{\Astore/[^/]+/graph\.json\z}

          def initialize(folder)
            @folder = folder
          end

          def call
            problems = unreadable + roadmap_problems + IndexProblems.new(@folder).call + graph_problems
            raise Failed, problems.join("; ") if problems.any?
          end

          private

          def unreadable = paths.reject { |path| File.readable?(@folder.path(path)) }.map { |path| "#{path} cannot be read" }

          def paths = [StoreFolder::LEGACY_INDEX, *@folder.intent_files, *roadmaps.files.map { |path| roadmaps.relative(path) }].select { |path| @folder.exist?(path) }

          def roadmaps = (@roadmaps ||= Roadmaps.new(@folder.root))

          def roadmap_problems
            return [] unless unreadable.empty?

            roadmaps.parse.values.flat_map(&:problems)
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
