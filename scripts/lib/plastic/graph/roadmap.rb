# frozen_string_literal: true

require_relative "record"

module Plastic
  module Graph
    # A roadmap: a named plan, held as rows instead of a hand-kept file.
    Roadmap = Data.define(:slug, :title, :goal, :opened_at, :updated_at, :origin_id) do
      include Record
    end

    # One wave of a roadmap: a titled group of items with its own goal and
    # done criteria, one per line.
    RoadmapBatch = Data.define(:roadmap, :position, :title, :goal, :done, :updated_at, :origin_id) do
      include Record

      def done_lines = done.to_s.lines(chomp: true)
    end

    # One planned piece of work inside a batch. `mark` is the owner's call
    # when an item is dropped; `intent_id` is set once the item is started.
    RoadmapItem = Data.define(:roadmap, :item, :batch, :position, :title, :goal, :done, :intent_id,
      :mark, :updated_at, :origin_id) do
      include Record

      def done_lines = done.to_s.lines(chomp: true)

      def dropped? = mark == "dropped"
    end

    # An edge between two items of the same roadmap: `to` waits for `from`.
    RoadmapEdge = Data.define(:roadmap, :from, :to, :kind, :origin_id) do
      include Record
    end

    # One line of a roadmap's log: a dated note about the roadmap itself.
    RoadmapLogLine = Data.define(:roadmap, :position, :at, :text, :session_id, :origin_id) do
      include Record
    end
  end
end
