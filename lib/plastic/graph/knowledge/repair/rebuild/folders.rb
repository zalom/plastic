# frozen_string_literal: true

require_relative "intent"
require_relative "../../sync_selection"

module Plastic
  module Graph
    module Knowledge
      module Repair
        module Rebuild
          # The old intent folders a repair rebuilds: the files that the layout names for rebuilding, by path relative to the
          # store folder, read into one Intent for each folder. `states` maps an intent id to its status when it is done or
          # abandoned, `ruled` gives the text an intent already holds as rulings and spec, and `graphed` holds the ids of the intents that already have graph nodes.
          class Folders
            def initialize(folder, paths, states:, ruled:, graphed: Set.new)
              @folder = folder
              @paths = paths
              @states = states
              @ruled = ruled
              @graphed = graphed
            end

            def paths = @paths.sort

            def intents = @intents ||= @paths.group_by { |path| File.dirname(path).sub(%r{/actions\z}, "").then { |dir| dir.split("/").first(2).join("/") } }.sort.map { |dir, paths| intent(dir, paths) }

            private

            def spec(dir) = @folder.exist?(spec_path(dir)) ? @folder.read(spec_path(dir)).force_encoding(Encoding::UTF_8) : ""

            def spec_path(dir) = "#{dir}/#{Layout.name(:spec)}"

            def intent(dir, paths)
              id = SyncSelection.intent_of(dir)
              files = paths.to_h { |path| [path.delete_prefix("#{dir}/"), @folder.read(path).force_encoding(Encoding::UTF_8)] }
              Intent.new(dir, files, status: @states.fetch(id, "open"), held: [@ruled.call(id), spec(dir)].join("\n"), graphed: @graphed.include?(id))
            end
          end
        end
      end
    end
  end
end
