# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Adds one item to a roadmap batch, after whichever items it waits on.
    class RoadmapAdd < Routine
      subject :slug
      argument :slug, label: "SLUG", text: "the roadmap"
      argument :position, label: "N", text: "the batch the item belongs to"
      argument :item_id, label: "ITEM", text: "the item's id"
      option :title, switch: "--title TITLE", text: "the item's title"
      option :goal, switch: "--goal GOAL", text: "the item's goal"
      option :done, switch: "--done TEXT", text: "one done criterion; repeat for more", repeatable: true
      option :after, switch: "--after ITEM", text: "an item this one waits on; repeat for more", repeatable: true
      writes :work

      workflow :code_add_roadmap_item, next: :noop
    end
  end
end
