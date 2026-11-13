# frozen_string_literal: true

require "digest"
require "json"
require_relative "print"

module Plastic
  module Graph
    module Prints
      # The graph.json print of an intent: the go-ahead, the verdicts, the nodes and the edges.
      module GraphPrint
        module_function

        def call(intent, rows)
          id = intent.intent_id
          approval = rows.approvals(id).first&.then { |row| plain(row) }
          parts = { "approval" => approval, "verdicts" => plain_all(rows.verdicts(id)), "nodes" => plain_all(rows.nodes(id)),
                    "edges" => plain_all(rows.edges(id)) }
          Print.text("#{intent.dir}/graph.json", :work, text(id, parts))
        end

        def text(id, parts)
          data = { "intent" => id, "approval" => nil, "verdicts" => [], "nodes" => [], "edges" => [] }.merge(parts)
          "#{JSON.pretty_generate(data)}\n"
        end

        def empty_sha(path)
          id = File.basename(File.dirname(path)).split("--", 2).first
          Digest::SHA256.hexdigest(text(id, {}))
        end

        def plain_all(records) = records.map { |record| plain(record) }

        def plain(record) = record.to_h.except(:origin_id).transform_keys(&:to_s)
      end
    end
  end
end
