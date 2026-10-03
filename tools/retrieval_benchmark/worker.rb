# frozen_string_literal: true

require "json"
require "time"
require_relative "../../scripts/lib/plastic"
require_relative "../../scripts/lib/plastic/graph/evidence_writer"

home, samples, ready, start, intent_id, path = ARGV.drop(1)
graphs = Plastic::Graph.open(home:, store: "store-1")
writer = Plastic::Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), graphs.retrieval.origin_id)
File.write(ready, "ready")
sleep 0.005 until File.exist?(start)
started_at = Time.now.utc.iso8601(6)
(samples.to_i * 10).times do |index|
  writer.write(intent_id, path, "concurrent writer revision #{index}")
  sleep 0.01
end
puts JSON.generate("started_at" => started_at, "finished_at" => Time.now.utc.iso8601(6))
