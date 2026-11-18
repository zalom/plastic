# frozen_string_literal: true

require "yaml"
require_relative "../../../code_workflow"
require_relative "../../config_settings"

module Plastic
  module Workflows
    module Code
      module Config
        # Writes one setting to the settings rows: under `global`, or under the
        # harness's section with --harness.
        class Set < CodeWorkflow
          clear_declarations

          sets :harness_words, :saved, :problem

          read "check the config file" do |context|
            context[:problem] = ConfigSettings.new(context).problem
          end

          gate "%{problem}", stops: :refusal, offers: "plastic config set KEY VALUE",
            because: "the file was edited by hand",
            words: "config.yml changed after it was printed from the settings, or it cannot be read",
            pass: ->(context) { context.problem.nil? }

          step "write the setting", done: ->(context) { context.saved },
            changes: { home: "The setting is written to the settings rows in plastic.db, and config.yml is printed from them" } do |context|
            settings = ConfigSettings.new(context)
            value = checked(settings, context.key, scalar(context.value))
            settings.set(context.key, value)
            context[:saved] = true
            context.row(context.key, value.to_s)
            context[:harness_words] = settings.harness_words
          end

          outcome :done, offers: "plastic config get %{key}%{harness_words}", because: "the setting is written"

          def self.scalar(text)
            value = YAML.safe_load(text)
            raise Usage, "a setting takes one value, not #{text}" if value.is_a?(Enumerable)

            [value].compact.fetch(0, text)
          rescue Psych::Exception
            text
          end

          def self.checked(settings, key, value)
            on_off = ConfigSettings::ON_OFF.include?(settings.current(key))
            raise Usage, "#{key} takes true or false" if on_off && !ConfigSettings::ON_OFF.include?(value)

            value
          end
        end
      end
    end
  end
end
