# frozen_string_literal: true

require_relative "../code_workflow"
require_relative "../commands/restore_sync"

module Plastic
  module Workflows
    # Asks the person which sync follows a restore, and leaves the choice to
    # the chain. With no person to ask, it tells the agent to ask.
    class AskRestoreSync < CodeWorkflow
      [facts, steps, outcomes].each(&:clear)

      sets :sync_choice, :overwrite, :merge, :ask_next

      step "ask which sync to run", done: ->(context) { !context.sync_choice.nil? } do |context|
        context[:overwrite] = false
        context[:merge] = false
        context[:ask_next] = format(Commands::RestoreSync::ASK_NEXT, store: context.store)
        context[:sync_choice] = Commands::RestoreSync.answer(context)
      end

      outcome :sync_down, if: Commands::RestoreSync.chosen("down")
      outcome :sync_up, if: Commands::RestoreSync.chosen("up")
      outcome :kept, if: Commands::RestoreSync.chosen("neither"), offers: "plastic next",
        because: "no sync ran; the rows and the files stay as they are"
      outcome :done, offers: "%{ask_next}",
        because: "a sync after a restore can undo it, so the person chooses"
    end
  end
end
