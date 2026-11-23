# frozen_string_literal: true

require_relative "work/node/release"
require_relative "work/driver/writer"

module Plastic
  module Graph
    class Writers
      # The databases, folder, retrieval and session every writer is built on.
      Scope = Data.define(:databases, :retrieval, :folder, :session, :clock) do
        # The driver claim writer and the release of a session's node claims, which keep no state of their own.
        def drivers = Work::Driver::Writer.new(databases, retrieval, clock:)

        def release = Work::Node::Release.new(databases, retrieval, clock:)
      end
    end
  end
end
