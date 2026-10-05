# frozen_string_literal: true

require_relative "../routine"
require_relative "../graph/work/node"

module Plastic
  module Commands
    # Moves a claimed node to done, judged by tests, tool, agent or owner.
    class NodeDone < Routine
      node_subject
      option :judge, switch: "--judge WHO", text: "tests, tool, agent or owner", required: true
      option :findings, switch: "--findings TEXT", text: "what the judge found", required: true
      option :repair, switch: "--repair", text: "record verification for an already done node", default: false
      writes :work

      def call
        raise CLI::Command::Usage, "--judge takes tests, tool, agent or owner" unless Graph::Work::Node::JUDGES.include?(parsed[:judge])

        raise CLI::Command::Usage, "--findings must describe the verification" if parsed[:findings].to_s.strip.empty?

        super
      end

      workflow :code_done_node, next: :noop
    end
  end
end
