# frozen_string_literal: true

require "json"
require_relative "print"
require_relative "graph_print"
require_relative "../knowledge/store_folder"

module Plastic
  module Graph
    module Prints
      # The store/index.json print: this installation's intents, the archives now in force and the clusters.
      module IndexPrint
        module_function

        def call(retrieval)
          data = { "store" => retrieval.store, "origin_id" => retrieval.origin_id,
                   "intents" => retrieval.intents.map(&:index_h), "archives" => archives(retrieval), "clusters" => clusters(retrieval.clusters) }
          Print.text(Knowledge::StoreFolder::INDEX, :work, "#{JSON.pretty_generate(data)}\n")
        end

        def archives(retrieval)
          completions = retrieval.completions.to_h { |row| [row.intent_id, GraphPrint.plain(row)] }
          marks(retrieval).map { |row| mark(row, completions) }
        end

        def marks(retrieval) = retrieval.archive_rows.reject(&:restored?).sort_by { |row| Knowledge::LuhmannId.segments(row.intent_id) }

        def mark(row, completions)
          id = row.intent_id
          { "intent_id" => id, "at" => row.at, "session_id" => row.session_id, "completion" => completions[id] }
        end

        def clusters(rows)
          rows.group_by(&:name).map { |name, members| { "name" => name, "intents" => luhmann(members.map(&:intent_id)) } }
        end

        def luhmann(ids) = ids.sort_by { |id| Knowledge::LuhmannId.segments(id) }
      end
    end
  end
end
