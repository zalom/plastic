# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Marks a roadmap item dropped. Its edges stay as rows.
    class RoadmapDrop < Routine
      subject :slug
      argument :slug, label: "SLUG", text: "the roadmap"
      argument :item_id, label: "ITEM", text: "the item to drop"
      writes :work

      workflow :code_drop_roadmap_item, next: :noop
    end
  end
end
