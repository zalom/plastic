# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Opens a ready roadmap item's intent, with its spec held in rows.
    class RoadmapOpen < Routine
      subject :slug
      argument :slug, label: "SLUG", text: "the roadmap"
      argument :item_id, label: "ITEM", text: "the item to open"
      writes :work, :knowledge, :references
      prints :roadmap, :intent

      workflow :code_open_roadmap_item, next: :noop
    end
  end
end
