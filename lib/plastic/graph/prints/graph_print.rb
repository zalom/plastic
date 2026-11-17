# frozen_string_literal: true

require "digest"
require "json"
require_relative "print"

module Plastic
  module Graph
    module Prints
      # The graph.json print of an intent: the go-ahead, the completion, the verdicts, the nodes with their runs and the edges.
      module GraphPrint
        module_function

        def call(intent, rows)
          id = intent.intent_id
          Print.text("#{intent.dir}/graph.json", text(id, parts(id, rows)))
        end

        def parts(id, rows)
          { "approval" => single(rows.approvals(id)), "completion" => single(rows.completions(id)), "verdicts" => plain_all(rows.verdicts(id)),
            "nodes" => nodes(rows.nodes(id)), "runs" => plain_all(rows.runs(id)), "edges" => plain_all(rows.edges(id)) }
        end

        def single(records) = records.first&.then { |row| plain(row) }

        def text(id, parts)
          data = { "intent" => id, "approval" => nil, "completion" => nil, "verdicts" => [], "nodes" => [], "runs" => [], "edges" => [] }.merge(parts)
          "#{JSON.pretty_generate(data)}\n"
        end

        def empty_sha(path)
          id = File.basename(File.dirname(path)).split("--", 2).first
          Digest::SHA256.hexdigest(text(id, {}))
        end

        # A node prints without `seen_at`: a renewal changes a row on this machine, never the files.
        def nodes(records) = records.map { |record| plain(record).except("seen_at") }

        def plain_all(records) = records.map { |record| plain(record) }

        def plain(record) = record.to_h.except(:origin_id).transform_keys(&:to_s)
      end
    end
  end
end
