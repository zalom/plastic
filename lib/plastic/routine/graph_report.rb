# frozen_string_literal: true

module Plastic
  class Routine < CLI::Command
    # The graph rows of a routine's answer: what it wrote and the files it printed.
    module GraphReport
      private

      def report_graphs
        output.row("wrote:", graphs.wrote)
        output.row("files:", graphs.printed)
      end

      def touches_graphs? = !self.class.opens_no_store?

      def routine_graphs = touches_graphs? ? graphs : {}
    end
  end
end
