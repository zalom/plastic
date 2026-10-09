# frozen_string_literal: true

require_relative "../routine"

module Plastic
  module Commands
    # Moves a claimed node to done, with its findings.
    class NodeDone < Routine
      node_subject
      option :findings, switch: "--findings TEXT", text: "what the work showed", required: true
      option :repair, switch: "--repair", text: "record verification for an already done node", default: false
      writes :work

      def call
        raise CLI::Command::Usage, "--findings must describe the verification" if parsed[:findings].to_s.strip.empty?

        super
      end

      workflow :code_done_node, next: :noop
    end
  end
end
