# frozen_string_literal: true

require "optparse"

module Plastic
  class CLI
    # Reads one call's argv against the arguments and options a command
    # declares. A missing required argument, an extra word or an unknown
    # switch is a Command::Usage error: exit 2. --json and --project belong
    # to every command.
    class Parser
      def initialize(arguments:, options:, banner:)
        @arguments = arguments
        @options = options
        @banner = banner
      end

      def parse(argv)
        values = @options.to_h { |o| [o.name, o.default] }
        switches(values).parse!(argv)
        values.merge(positional(argv))
      end

      private

      def switches(values)
        OptionParser.new do |o|
          o.banner = @banner
          o.on("--json") { values[:json] = true }
          o.on("--project SLUG") { |slug| values[:project] = slug }
          @options.each { |option| o.on(option.switch, option.text) { |value| values[option.name] = value } }
        end
      end

      def positional(words)
        values = @arguments.each_with_index.to_h { |argument, index| [argument.name, value_of(argument, words, index)] }
        extra = @arguments.any?(&:rest) ? [] : words.drop(@arguments.size)
        raise Command::Usage, "unexpected #{extra.join(" ")}" if extra.any?

        values
      end

      def value_of(argument, words, index)
        value = argument.rest ? words[index..]&.join(" ") : words[index]
        return value unless blank?(value)
        raise Command::Usage, "missing #{argument.label}" unless argument.optional

        nil
      end

      def blank?(value) = value.nil? || value.strip.empty?
    end
  end
end
