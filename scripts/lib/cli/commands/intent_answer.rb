# frozen_string_literal: true

require_relative "intent_command"

# `plastic intent answer` - closes a `needs_decision` node with the owner's
# ruling (`runner answer`, run through Legacy).
module Plastic
  class CLI
    module Commands
      class IntentAnswer < IntentCommand
        USAGE_LINE = 'plastic intent answer ID --node NODE --decision "TEXT" [--json]'

        SCRIPT = "runner"
        AFTER = "plastic intent step ID"
        BECAUSE = "step resumes the graph past the node this decision just closed"

        def call
          raise Usage, "--node is required" if options[:node].to_s.empty?
          raise Usage, "--decision is required" if options[:decision].to_s.empty?

          super
        end

        private

        def switches(parser)
          parser.on("--node ID") { |v| @options[:node] = v }
          parser.on("--decision TEXT") { |v| @options[:decision] = v }
        end

        def script_arguments
          ["answer", intent_dir, "--node", options[:node], "--answer", options[:decision]]
        end
      end
    end
  end
end
