# frozen_string_literal: true

module Plastic
  class CLI
    class Command
      # The usage line of a command and one line for each argument, option and
      # the switches every command takes.
      class Help
        def initialize(tool, usage_line)
          @tool = tool
          @usage_line = usage_line
        end

        def lines = [@usage_line, *details]

        private

        def details
          arguments = @tool.arguments.map { |argument| line(argument.usage, argument.text) }
          options = @tool.options.map { |option| line(option.switch, option.text) }
          [*arguments, *options, "        --json", "        --project SLUG"]
        end

        def line(syntax, text) = format("        %-28s %s", syntax, text)
      end
    end
  end
end
