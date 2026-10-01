# frozen_string_literal: true

module Plastic
  class CLI
    class Command
      # One switch a command takes, such as --dir DIR, and its value when the
      # call leaves it out.
      Option = Data.define(:name, :switch, :text, :default, :repeatable) do
        def usage = "[#{switch}]"

        # Teaches `parser` this switch; its value lands in `values`. A
        # repeatable option appends each occurrence instead of replacing it,
        # into a new array each time: `values[name]` starts as this Option's
        # one shared `default` array, and appending in place would pollute
        # every later call with every earlier call's values.
        def add_to(parser, values)
          return parser.on(switch, text) { |value| values[name] += [value] } if repeatable

          parser.on(switch, text) { |value| values[name] = value }
        end
      end
    end
  end
end
