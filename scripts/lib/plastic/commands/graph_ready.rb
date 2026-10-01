# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Lists the nodes ready to claim: open, with every need done.
    class GraphReady < Routine
      subject :intent_id
      argument :intent_id, label: "ID", text: "the intent"
      reads :work
      workflow :code_ready_graph, next: :noop
    end
  end
end
