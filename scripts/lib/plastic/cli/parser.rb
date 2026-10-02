# frozen_string_literal: true

require "optparse"

module Plastic
  class CLI
    # Reads one call's argv against the arguments and options a command
    # declares. A missing required argument or switch, an extra word or an unknown
    # switch is a Command::Usage error: exit 2. --json and --project belong
    # to every command.
    class Parser
      def initialize(arguments:, options:, banner:)
        @arguments = arguments
        @options = options
        @banner = banner
      end

      # The values of one call. `argv` stays as given; the words left after
      # the switches are the positional arguments.
      def parse(argv)
        values = @options.to_h { |option| [option.name, option.default] }
        words = switches(values).parse(argv)
        refuse_missing(values)
        values.merge(positional(words))
      end

      # Every tool takes --json and --project.
      def self.common_switches(banner, values)
        OptionParser.new(banner).tap do |parser|
          parser.on("--json") { values[:json] = true }
          parser.on("--project SLUG") { |slug| values[:project] = slug }
        end
      end

      private

      def switches(values) = @options.each_with_object(self.class.common_switches(@banner, values)) { |option, parser| option.add_to(parser, values) }

      def positional(words)
        refuse_extra(words)
        @arguments.each_with_index.to_h { |argument, index| [argument.name, argument.read(words, index)] }
      end

      def refuse_missing(values)
        missing = @options.find { |option| option.required && values[option.name].nil? }
        raise Command::Usage, "missing #{missing.switch.split.first}" if missing
      end

      def refuse_extra(words)
        extra = @arguments.any?(&:rest) ? [] : words.drop(@arguments.size)
        raise Command::Usage, "unexpected #{extra.join(" ")}" if extra.any?
      end
    end
  end
end
