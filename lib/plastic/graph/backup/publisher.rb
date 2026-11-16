# frozen_string_literal: true

require_relative "target"
require_relative "writer"

module Plastic
  module Graph
    module Backup
      # Writes a complete backup folder.
      class Publisher
        def initialize(target, now:, databases: nil, live: ->(_line) {}, **mode)
          @target = target
          @writer = Writer.new(target.root, target.slug, now:, copy: Copy.new(now:, databases:, live:), **mode)
        end

        # The backup written, or nil when an automatic backup had nothing to do.
        def call = @writer.call
      end
    end
  end
end
