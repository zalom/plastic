# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Prints one intent's nodes and edges, then reprints graph.json from rows.
    class GraphShow < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the intent"
      writes :work
      workflow :code_show_graph, next: :noop
    end
  end
end
