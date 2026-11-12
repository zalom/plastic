# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Roadmap
      # Marks a roadmap item dropped. Its edges stay as rows.
      class Drop < Routine
        subject :slug
        argument :slug, label: "SLUG", text: "the roadmap"
        argument :item_id, label: "ITEM", text: "the item to drop"
        writes :work
        prints :roadmap
        previews

        workflow :code_drop_roadmap_item, next: :noop
      end
    end
  end
end
