# frozen_string_literal: true

require_relative "roadmap_workflow"

module Plastic
  module Workflows
    module Code
      module Roadmap
        # Marks a roadmap item dropped. Its edges stay; items after it stop
        # waiting for it, since a dropped predecessor counts as resolved.
        class Drop < RoadmapWorkflow
          clear_declarations

          roadmap_gate

          sets :item, :dropped

          read "find the item" do |context|
            context[:item] = context.retrieval.roadmap_items(context.slug).find { |item| item.item == context.item_id }
          end

          gate "no item %{item_id} on roadmap %{slug}", stops: :failure, pass: ->(context) { !context.item.nil? }

          step "drop the item", done: ->(context) { context.dropped } do |context|
            context[:dropped] = context.work.drop_item(context.slug, context.item_id)
          end

          read "say what was dropped" do |context|
            context.print("dropped: #{context.item_id}")
          end

          outcome :done, offers: "plastic roadmap next %{slug}", because: "item %{item_id} no longer blocks its successors"
        end
      end
    end
  end
end
