# frozen_string_literal: true

require_relative "../../../code_workflow"
require_relative "../../config_settings"

module Plastic
  module Workflows
    module Code
      module Config
        # Prints the value of one setting. It writes nothing.
        class Get < CodeWorkflow
          clear_declarations

          sets :harness_words

          read "print the setting" do |context|
            settings = ConfigSettings.new(context)
            context.row(context.key, settings.current(context.key).to_s)
            context[:harness_words] = settings.harness_words
          end

          outcome :done, offers: "plastic config set %{key} VALUE%{harness_words}", because: "the setting is printed"
        end
      end
    end
  end
end
