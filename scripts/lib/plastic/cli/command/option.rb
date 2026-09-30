# frozen_string_literal: true

module Plastic
  class CLI
    class Command
      # One switch a command takes, such as --dir DIR, and its value when the
      # call leaves it out.
      Option = Data.define(:name, :switch, :text, :default) do
        def usage = "[#{switch}]"

        # Teaches `parser` this switch; its value lands in `values`.
        def add_to(parser, values)
          parser.on(switch, text) { |value| values[name] = value }
        end
      end
    end
  end
end
