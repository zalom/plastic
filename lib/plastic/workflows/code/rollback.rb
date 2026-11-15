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
        clear_declarations

        sets :command

        read "name the switch command" do |context|
          installed = ReleaseUpdate.of(context).installed
          context[:command] = ReleaseCommand.of(context.scope).switch(installed.active_version, context.target || installed.previous_version)
        end

        read "say what a rollback means for the stored data" do |context|
          context.print("a release older than this one cannot run on a home that a newer release opened")
        end

        outcome :done, offers: "%{command}", because: "this command switches the active release; rollback changed nothing"
      end
    end
  end
end
