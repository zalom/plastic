# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../config_settings"

module Plastic
  module Workflows
    module Code
      module Config
        # Lists every setting with its value: the global settings, or those of
        # one harness with --harness. It writes nothing.
        class List < CodeWorkflow
          clear_declarations

          sets :harness_words

          read "print each setting with its value" do |context|
            settings = ConfigSettings.new(context)
            settings.entries.each { |key, value| context.row(key, value.to_s) }
            context[:harness_words] = settings.harness_words
          end

          outcome :done, offers: "plastic config set KEY VALUE%{harness_words}", because: "the settings are listed"
        end
      end
    end
  end
end
