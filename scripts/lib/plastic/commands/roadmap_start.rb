# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Opens a ready roadmap item's intent, with its spec held in rows.
    class RoadmapStart < Routine
      subject :slug
      argument :slug, label: "SLUG", text: "the roadmap"
      argument :item_id, label: "ITEM", text: "the item to start"
      writes :work, :knowledge, :references

      workflow :code_start_roadmap_item, next: :noop
    end
  end
end
