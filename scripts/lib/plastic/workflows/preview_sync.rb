# frozen_string_literal: true

require_relative "../code_workflow"

module Plastic
  module Workflows
    # Previews the same sync in a copy before the normal write workflow.
    class PreviewSync < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      read "preview the sync in an isolated copy" do |context|
        if context.dry_run
          context.work.preview_sync({ overwrite: context.overwrite, merge: context.merge }).each { |line| context.print(line) }
          context.print("preview complete; the original store was not changed")
        end
      end

      outcome :done, if: ->(context) { context.dry_run }, offers: "plastic sync up",
        because: "the preview wrote only to a disposable copy"
      outcome :continue, offers: "plastic sync up", because: "apply the requested sync"
    end
  end
end
