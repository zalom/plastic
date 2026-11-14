# frozen_string_literal: true

require_relative "entry"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The printed files a person edited, for the prints a command declares. A path with no row to print is left alone.
        class HandEdits
          def initialize(retrieval, folder)
            @retrieval = retrieval
            @folder = folder
          end

          def call(kinds, intent_id:, slug:)
            printed = @retrieval.printed
            prints(kinds, intent_id, slug).select { |print| entry(print, printed).hand_edited? }.map(&:path)
          end

          private

          def entry(print, printed) = Entry.new(print.path, @folder.digest(print.path), printed[print.path], print)

          def prints(kinds, intent_id, slug)
            kinds.flat_map { |kind| (kind == :roadmap) ? roadmap(slug) : [Prints.index(@retrieval), *intent(kind, intent_id)] }.uniq(&:path)
          end

          def intent(kind, intent_id)
            row = (kind == :intent && intent_id) ? @retrieval.intent(intent_id) : nil
            row ? Prints.of_intent(@retrieval, row) : []
          end

          def roadmap(slug) = (slug && @retrieval.roadmap(slug)) ? [Prints.roadmap(@retrieval, slug)] : []
        end
      end
    end
  end
end
