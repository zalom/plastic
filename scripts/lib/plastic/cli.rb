# frozen_string_literal: true

require_relative "cli/command"
require_relative "cli/table"

module Plastic
  class CLI
    # The command the words name: the longest table entry that starts argv,
    # so `auto lock renew` wins over `auto lock`.
    def self.find(argv, table = TABLE)
      table.keys.select { |name| argv.take(name.split.size) == name.split }.max_by(&:size)
    end

    # The class that runs a command, loaded only when called. The class names
    # its file: Commands::IntentEnd is commands/intent_end.rb.
    def self.tool(name, table = TABLE)
      klass, _summary = table.fetch(name)
      require_relative file_of(klass) unless Plastic.const_defined?(klass)
      Plastic.const_get(klass)
    end

    def self.file_of(klass)
      klass.split("::").map { |part| part.gsub(/(?<=[a-z0-9])(?=[A-Z])/, "_").downcase }.join("/")
    end

    # The whole of bin/plastic: find the command, hand it the rest of argv and
    # its own words. A hook reads its event from the environment's input;
    # other tools ignore it.
    def self.call(argv, out: $stdout, err: $stderr, environment: Command::Environment.current, table: TABLE)
      name = find(argv.empty? ? ["help"] : argv, table)
      unless name
        err.puts "plastic: no command #{argv.first(2).join(" ").inspect}; plastic help lists them"
        return Command::USAGE
      end

      tool(name, table).call(argv.drop(name.split.size), words: name, out:, err:, environment:)
    end
  end
end
