# frozen_string_literal: true

require "json"
require_relative "print"
require_relative "../knowledge/store_folder"

module Plastic
  module Graph
    module Prints
      # The store/index.json print: this installation's intents and the clusters.
      module IndexPrint
        module_function

        def call(retrieval)
          data = { "store" => retrieval.store, "origin_id" => retrieval.origin_id,
                   "intents" => retrieval.unarchived_intents.map(&:index_h), "clusters" => clusters(retrieval.clusters) }
          Print.text(Knowledge::StoreFolder::INDEX, :work, "#{JSON.pretty_generate(data)}\n")
        end

        def clusters(rows)
          rows.group_by(&:name).map { |name, members| { "name" => name, "intents" => luhmann(members.map(&:intent_id)) } }
        end

        def luhmann(ids) = ids.sort_by { |id| Knowledge::LuhmannId.segments(id) }
      end
    end
  end
end
