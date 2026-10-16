# frozen_string_literal: true

require_relative "../harnesses"
require_relative "session_rows"

module Plastic
  module Harnesses
    # The session a call runs in when the session variables of two harnesses
    # are set, as when one harness runs inside the other: the one whose row
    # started last, else the one of the nearest ancestor process, else the
    # first in registry order.
    class Innermost
      def initialize(env:, processes:, plastic_home:)
        @env = env
        @processes = processes
        @plastic_home = plastic_home
      end

      def session
        ids = Harnesses.sessions(@env)
        first, *others = ids.values.uniq
        return first if others.empty?

        SessionRows.new(@plastic_home).latest([first, *others]) || ids[Harnesses.nearest(@processes, among: ids.keys)&.name] || first
      end
    end
  end
end
