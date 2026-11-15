# frozen_string_literal: true

require_relative "../../routine"

module Plastic
  module Commands
    module Graph
      # Says where each named store's work stopped and what runs next. It reads
      # the rows and writes nothing.
      class Resume < Routine
        opens_no_store

        option :stores, switch: "--stores LIST", text: "the stores to read, comma separated: registered projects or global; the call's own store when left out"

        workflow :code_resume_graph, next: :noop
      end
    end
  end
end
