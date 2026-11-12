# frozen_string_literal: true

require_relative "../up"
require_relative "../../../../code_workflow"

module Plastic
  module Workflows
    module Code
      module Sync
        class Up
          # Previews the same sync in a copy before the normal write workflow.
          class Preview < CodeWorkflow
            [facts, steps, outcomes].each(&:clear)

            read "preview the sync in an isolated copy" do |context|
              if context.dry_run
                context.work.preview_sync({ overwrite: context.overwrite, merge: context.merge }).each { |line| context.print(line) }
                context.print("preview complete; the original store was not changed")
              end
            end

            outcome :done, if: ->(context) { context.dry_run }, offers: "%{original_command}",
              because: "the preview wrote only to a disposable copy"
            outcome :continue, offers: "plastic sync up", because: "apply the requested sync"
          end
        end
      end
    end
  end
end
