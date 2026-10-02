# frozen_string_literal: true

require_relative "../../scripts/lib/plastic"
require_relative "../../scripts/lib/plastic/graph/evidence_writer"

home = ARGV.fetch(1)
samples = Integer(ARGV.fetch(2))
graphs = Plastic::Graph.open(home:, store: "store-1")
writer = Plastic::Graph::EvidenceWriter.new(graphs.databases.fetch(:knowledge), graphs.retrieval.origin_id)
samples.times { |index| writer.write("concurrent", "writer.md", "concurrent writer revision #{index}") }
