# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Graph
      # Lists every intent in agent delivery whose driver claim or node claim lapsed, and names the command that
      # restarts it. It reads the rows, and it renews no claim, so a stalled helper's claim stays lapsed.
      class Lapsed < Routine
        opens_no_store
        renews_no_claims

        option :stores, switch: "--stores LIST", text: "the stores to read, comma separated: registered projects or global; the call's own store when left out"

        workflow :code_lapsed_graph, next: :noop
      end
    end
  end
end
