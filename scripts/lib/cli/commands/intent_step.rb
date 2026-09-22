# frozen_string_literal: true

require_relative "intent_command"
require_relative "../intent_progress"
require_relative "../../runner_core"

# `plastic intent step` - runs the graph's next ready step (`runner step`, run
# through Legacy). Direct intents report their next checklist item. Graph
# execution requires ownership, resolved by the same rules as the runner.
module Plastic
  class CLI
    module Commands
      class IntentStep < IntentCommand
        USAGE_LINE = "plastic intent step ID [--json]"

        SCRIPT = "runner"
        AFTER = "plastic intent step ID"
        BECAUSE = "call step again after each dispatched node returns"

        def call
          intent_dir
          command, reason = IntentProgress.new(scope, id).decision
          return @output.next_step(command, because: reason) if command == "none"

          if graph?
            return unless graph_owner?

            super
          elsif command == "plastic intent step #{id}"
            item = IntentScreen.checklist_items(intent_dir).find { |entry| !entry[:done] }
            @output.row("work", item[:text])
            @output.row("checklist", File.join(intent_dir, "checklist.md"))
            @output.next_step("none", because: "perform this checklist item, record its verification, then run plastic intent show #{id} --project #{scope.slug}")
          else
            @output.next_step(command, because: reason)
          end
        end

        private

        def graph_owner?
          session = RunnerCore.resolve_owning_session(intent_dir, explicit: nil,
            env_session: @env["CLAUDE_CODE_SESSION_ID"], store: scope.store, intent_id: id)
          return true if session
          raise Refusal, "intent #{id} is held by another session; inspect with plastic auto lock status #{id} --project #{scope.slug}" if Lock.read(intent_dir)

          @output.next_step("plastic auto take #{id}", because: "graph execution requires this session to take the delivery lock")
          false
        end

        def graph?
          File.exist?(File.join(intent_dir, "graph.md"))
        end

        def script_arguments
          ["step", intent_dir]
        end
      end
    end
  end
end
