# frozen_string_literal: true

require_relative "../routine"
require_relative "../graph/node"

module Plastic
  module Commands
    # Moves a claimed node to done, judged by tests, tool, agent or owner.
    class NodeDone < Routine
      node_subject
      option :judge, switch: "--judge WHO", text: "tests, tool, agent or owner"
      option :findings, switch: "--findings TEXT", text: "what the judge found"
      writes :work

      def call
        raise CLI::Command::Usage, "--judge takes tests, tool, agent or owner" unless Graph::Node::JUDGES.include?(parsed[:judge])

        super
      end

      workflow :code_done_node, next: :noop
    end
  end
end
