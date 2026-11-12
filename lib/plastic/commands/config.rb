# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../cli/screen"
require_relative "config_scope"

module Plastic
  module Commands
    # Shows the on/off settings on the choice screen, the ones that are on
    # already picked, and writes each one the person changed. See
    # docs/help/choice-screen.md.
    class Config < CLI::Command
      include ConfigScope

      QUESTION = "Which settings are on?"

      argument :answer, label: "ANSWER", text: "the person's answer to the numbered list", optional: true

      def self.changes(toggles, picked)
        toggles.to_h { |key, _on| [key, picked.include?(key)] }.reject { |key, on| toggles[key] == on }
      end

      def call
        result = pick(choices)
        save(result.labels) if result.is_a?(CLI::Screen::Chosen)
        output.next_step("plastic config list#{harness_words}", because: "the person left with no change") if result.is_a?(CLI::Screen::Left)
      end

      private

      def toggles = config.entries.select { |_key, value| ON_OFF.include?(value) }

      def choices = toggles.map { |key, on| CLI::Screen::Choice.new(label: key, chosen: on) }

      def pick(choices)
        text = parsed[:answer]
        return CLI::Screen::Answer.new(choices).call(text) if text

        CLI::Screen.for(environment, output:).ask(QUESTION, choices, command: "plastic config#{harness_words}")
      end

      def save(picked)
        changed = Config.changes(toggles, picked)
        changed.each { |key, on| write(key, on) }
        output.next_step("plastic config list#{harness_words}", because: changed.empty? ? "nothing changed" : "the changed settings are written")
      end

      def write(key, on)
        config.set(key, on)
        output.row(key, on.to_s)
      end
    end
  end
end
