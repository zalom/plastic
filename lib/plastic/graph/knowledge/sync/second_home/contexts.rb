# frozen_string_literal: true

require_relative "../../reader/context_file"
require_relative "../../../../layout"

module Plastic
  module Graph
    module Knowledge
      class Sync
        class SecondHome
          # The context.json files of the intents this home knows and holds no context or discovery for.
          class Contexts
            def initialize(folder, retrieval, folders, known)
              @folder = folder
              @retrieval = retrieval
              @folders = folders
              @known = known
            end

            def paths = files.select { |path, id| file(path, id).usable? }.map(&:first)

            def problems = files.to_h { |path, id| [path, file(path, id).problem] }.compact

            private

            def files
              @folder.intent_dirs.filter_map do |dir|
                path = File.join(dir, Layout.name(:context))
                id = File.basename(dir).split("--").first
                [path, id] if @known.include?(id) && readable_dir?(dir) && @folder.exist?(path) && unheld?(id)
              end
            end

            def readable_dir?(dir) = @folders.nil? || !@folders.unreadable.include?(dir)

            def unheld?(id) = [:contexts, :discoveries].all? { |held| @retrieval.structure.public_send(held, id).empty? }

            def file(path, id) = Reader::ContextFile.new(@folder.read(path), id, path)
          end
        end
      end
    end
  end
end
