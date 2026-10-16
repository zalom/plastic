# frozen_string_literal: true

require_relative "preview_sync"

module Plastic
  module Workflows
    # Previews sync down in a copy before the normal write workflow.
    class PreviewSyncDown < PreviewSync
      [facts, steps, outcomes].each(&:clear)

      read "preview the sync" do |context|
        if context.dry_run
          context.work.preview_sync({ overwrite: context.overwrite, merge: context.merge }, direction: :down)
            .each { |line| context.print(line) }
          context.print("preview complete; the original store was not changed")
        end
      end

      outcome :done, if: ->(context) { context.dry_run }, offers: "%{original_command}",
        because: "the preview wrote only to a disposable copy"
      outcome :continue, offers: "plastic sync down", because: "apply the requested sync"
    end
  end
end
