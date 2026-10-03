# frozen_string_literal: true

require_relative "../roadmap"
require "forwardable"
require_relative "../../retrieval/evidence/writer"
require_relative "state"

module Plastic
  module Graph
    module Knowledge
      class Roadmap
        # Opens a ready roadmap item's intent, with its spec held in rows.
        class ItemStart
          extend Forwardable

          def_delegators :@writers, :databases, :retrieval

          def initialize(writers)
            @writers = writers
          end

          # Returns [intent_id, problem, kind]; kind is :failure or :refusal, nil on success.
          def call(slug, item_id)
            item = retrieval.roadmap_items(slug).find { |row| row.item == item_id }
            item ? start(slug, item) : [nil, "no item #{item_id} on roadmap #{slug}", :failure]
          end

          private

          def start(slug, item)
            refusal = item.start_refusal(State.of(item, retrieval))
            refusal ? [nil, refusal, :refusal] : open_intent(slug, item)
          end

          def open_intent(slug, item)
            intent_id = @writers.intents.write(title: item.title).intent_id
            write_spec(intent_id, item.spec_body(retrieval.batches(slug)))
            @writers.roadmaps.start_item(slug, item.item, intent_id)
            link_source(intent_id, slug)
            [intent_id, nil, nil]
          end

          def write_spec(intent_id, body) = Retrieval::Evidence::Writer.new(databases.fetch(:knowledge), retrieval.origin_id).write(intent_id, "spec.md", body)

          def link_source(intent_id, slug) = @writers.links.add_link(from_ref: intent_id, to_ref: "roadmap:#{slug}", kind: "source")
        end
      end
    end
  end
end
