# frozen_string_literal: true

module Plastic
  module Graph
    class Sync
      # How one sync settles a conflict. `overwrite` is false for none, nil
      # for every conflict, or the path of one record, and a conflict it names
      # takes the direction's side. `merge` applies the one-sided changes and
      # leaves the conflicts as they are.
      class Resolution
        SIDES = { up: :read, down: :print }.freeze

        attr_reader :direction

        def initialize(direction, root, options)
          @direction = direction
          overwrite = options.fetch(:overwrite, false)
          @overwrite = overwrite.is_a?(String) ? overwrite.delete_prefix("#{root}/") : overwrite
          @merge = options.fetch(:merge, false)
        end

        def side = SIDES.fetch(direction)

        def up? = direction == :up

        def overwrites?(path) = [nil, path].include?(@overwrite)

        # One-sided changes go through while conflicts wait: --merge, or --overwrite PATH.
        def merging? = @merge || path?

        # The overwrite path when it names none of `paths`.
        def unknown_path(paths)
          @overwrite if path? && !paths.include?(@overwrite)
        end

        private

        def path? = @overwrite.is_a?(String)
      end
    end
  end
end
