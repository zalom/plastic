# frozen_string_literal: true

require_relative "cli/command"
require_relative "cli/table"

module Plastic
  # The command line of the kernel: finds the command that argv names in
  # TABLE, loads its class, and hands it the call.
  class CLI
    # The command the words name: the longest table entry that starts argv,
    # so `auto lock renew` wins over `auto lock`.
    def self.find(argv, table = TABLE)
      table.keys.select { |name| starts?(argv, name.split) }.max_by(&:size)
    end

    def self.starts?(argv, words) = argv.take(words.size) == words

    # The class that runs a command, loaded only when called. The class names
    # its file: Commands::IntentEnd is commands/intent_end.rb.
    def self.tool(name, table = TABLE)
      klass, _summary = table.fetch(name)
      require_relative file_of(klass) unless Plastic.const_defined?(klass)
      Plastic.const_get(klass)
    end

    def self.file_of(klass) = klass.split("::").map { |part| Plastic.snake(part) }.join("/")

    # The whole of bin/plastic: find the command, hand it the rest of argv and
    # its own words. A hook reads its event from the environment's input;
    # other tools ignore it.
    def self.call(argv, environment: Command::Environment.current, table: TABLE)
      name = find(argv.empty? ? ["help"] : argv, table)
      return tool(name, table).call(argv.drop(name.split.size), words: name, environment:) if name

      environment.err.puts "plastic: no command #{argv.first(2).join(" ").inspect}; plastic help lists them"
      Command::USAGE
    end

    # The whole of bin/plastic: run a shipped command, list the shipped
    # commands for `plastic help`, and name a command that has no stage yet
    # instead of blaming the words the owner typed.
    def self.bin_call(argv, environment: Command::Environment.current, table: TABLE)
      return list(table, environment) if argv.empty? || %w[help --help -h].include?(argv.first)

      name = find(argv, table)
      return tool(name, table).call(argv.drop(name.split.size), words: name, environment:) if name

      environment.err.puts "plastic #{argv.join(" ")} is not in this build yet; it lands with its stage"
      Command::USAGE
    end

    def self.list(table, environment)
      table.each { |name, (_, summary)| environment.out.puts format("%-14s %s", name, summary) }
      Command::OK
    end
  end
end
