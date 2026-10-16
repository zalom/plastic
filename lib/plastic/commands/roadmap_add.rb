# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Adds one item to a roadmap batch, with the items it needs.
    class RoadmapAdd < Routine
      subject :slug
      argument :slug, label: "SLUG", text: "the roadmap"
      argument :position, label: "N", text: "the batch the item belongs to"
      argument :item_id, label: "ITEM", text: "the item's id"
      option :title, switch: "--title TITLE", text: "the item's title"
      option :goal, switch: "--goal GOAL", text: "the item's goal"
      option :done, switch: "--done TEXT", text: "one done criterion; repeat for more", repeatable: true
      option :needs, switch: "--needs ITEM", text: "an item this one needs; repeat for more", repeatable: true
      writes :work
      prints :roadmap

      workflow :code_add_roadmap_item, next: :noop
    end
  end
end
