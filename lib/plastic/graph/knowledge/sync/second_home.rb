# frozen_string_literal: true

require "json"
require_relative "../reader"
require_relative "../reader/context_file"
require_relative "../reader/roadmap_file"
require_relative "../store_folder"
require_relative "archived_intents"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The files a second home reads on its first sync up, because it holds no rows for what they carry: the
        # roadmap files with no roadmap row and the context.json of an intent that holds no context and no
        # discovery. A part that cannot be read is a broken part, named by its path and left as it is; every good part is read.
        class SecondHome
          OLDER_FORM = "is in an older form that this release does not read"

          def initialize(folder, retrieval, folders = nil, active: true)
            @folder = folder
            @retrieval = retrieval
            @folders = folders
            @active = active
          end

          NONE = new(nil, nil, active: false)

          # Each part that cannot be read, by path, with the reason.
          def problems = (@problems ||= @active ? roadmap_problems.merge(context_problems, cluster_problems) : {})

          # The paths the reader turns into rows: roadmap files and context.json files.
          def paths = @active ? [*roadmaps, *contexts] : []

          def size = paths.size

          private

          def roadmap_files = @folder.roadmap_files.reject { |path| @retrieval.roadmap(File.basename(path, ".md")) }

          def roadmaps = roadmap_files.select { |path| roadmap_problem(path).nil? }

          def roadmap_problems = roadmap_files.to_h { |path| [path, roadmap_problem(path)] }.compact

          def roadmap_problem(path)
            slug = File.basename(path, ".md")
            text = @folder.read(path)
            return "roadmaps/#{slug}.md #{OLDER_FORM}" unless Reader::RoadmapFile.form?(text)

            Reader::RoadmapFile.new(slug, text, clock: @retrieval.clock)
            nil
          rescue Invalid => error
            error.message
          end

          def context_files
            @folder.intent_dirs.filter_map do |dir|
              path = "#{dir}/context.json"
              id = File.basename(dir).split("--").first
              [path, id] if known.include?(id) && readable_dir?(dir) && @folder.exist?(path) && unheld?(id)
            end
          end

          def readable_dir?(dir) = @folders.nil? || !@folders.unreadable.include?(dir)

          def unheld?(id) = @retrieval.contexts(id).empty? && @retrieval.discoveries(id).empty?

          def contexts = context_files.select { |path, id| context_file(path, id).problem.nil? && context_file(path, id).rows.any? }.map(&:first)

          def context_problems = context_files.to_h { |path, id| [path, context_file(path, id).problem] }.compact

          def context_file(path, id) = Reader::ContextFile.new(@folder.read(path), id, path, clock: @retrieval.clock)

          def known
            @known ||= [*@retrieval.intents.map(&:intent_id), *Array(@folders&.intents).map(&:intent_id),
              *ArchivedIntents.new(@folder, @retrieval).missing.map { |mark| mark["intent_id"] }]
          end

          def index_file = Reader::IndexFile.new(@folder.read(StoreFolder::INDEX), @retrieval.origin_id, clock: @retrieval.clock)

          def cluster_entries
            return [] unless @folder.exist?(StoreFolder::INDEX) && @retrieval.clusters.empty?

            index_file.cluster_rows
          rescue JSON::ParserError, Invalid
            []
          end

          def cluster_problems
            lacking = cluster_entries.map { |row| row[:intent_id] }.uniq - known
            lacking.empty? ? {} : { StoreFolder::INDEX => "lists a cluster with #{lacking.map { |id| "intent #{id}" }.join(", ")}, which this home lacks" }
          end
        end
      end
    end
  end
end
