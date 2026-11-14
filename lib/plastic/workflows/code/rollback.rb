# frozen_string_literal: true

require_relative "../../code_workflow"
require_relative "../release_command"
require_relative "../release_update"

module Plastic
  module Workflows
    module Code
      # Names the command that switches to the named release or the previous
      # one. It changes nothing itself.
      class Rollback < CodeWorkflow
        [facts, steps, outcomes].each(&:clear)

        sets :command

        read "name the switch command" do |context|
          activation = ReleaseUpdate.of(context).activation
          context[:command] = ReleaseCommand.of(context.scope).switch(activation.active_version, context.target || activation.previous_version)
        end

        outcome :done, offers: "%{command}", because: "this command switches the active release; rollback changed nothing"
      end
    end
  end
end
