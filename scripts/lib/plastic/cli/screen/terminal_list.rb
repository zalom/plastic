# frozen_string_literal: true

require_relative "outcomes"

module Plastic
  class CLI
    class Screen
      # The list in the terminal: the preselected items start picked, Space
      # toggles, Enter confirms and Ctrl+C leaves with no change.
      class TerminalList
        HELP = "(Space toggles, Ctrl+A picks all, Enter confirms, Ctrl+C leaves with no change)"

        # A prompt on `input` and `stream`, loaded only when a person is there to answer it.
        def self.prompt(input, stream, env: ENV)
          require "tty-prompt"
          TTY::Prompt.new(input:, output: stream, env:, interrupt: :error, enable_color: false)
        end

        def initialize(prompt)
          @prompt = prompt
        end

        def call(question, choices)
          labels = choices.map(&:label)
          picked = @prompt.multi_select(question, labels, default: Choice.preselected(choices), help: HELP,
            show_help: :always, echo: false, per_page: labels.size)
          Chosen.new(labels: labels & picked)
        rescue TTY::Reader::InputInterrupt
          Left.new
        end
      end
    end
  end
end
