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
      dispatch(argv.empty? ? ["help"] : argv, table, environment) do
        "plastic: no command #{argv.first(2).join(" ").inspect}; plastic help lists them"
      end
    end

    # The whole of bin/plastic: run a shipped command, list the shipped
    # commands for `plastic help`, and name a command that has no stage yet
    # instead of blaming the words the owner typed.
    def self.bin_call(argv, environment: Command::Environment.current, table: TABLE)
      command = argv.first
      return list(argv, table, environment) if argv.empty? || %w[--help -h].include?(command)
      return help(argv, table, environment) if command == "help"

      dispatch(argv, table, environment) { "plastic #{argv.join(" ")} is not in this build yet; it lands with its stage" }
    end

    # Runs the command the words name, or prints the block's line and exits 2.
    def self.dispatch(argv, table, environment)
      name = find(argv, table)
      return tool(name, table).call(argv.drop(name.split.size), words: name, environment:) if name

      environment.err.puts yield
      Command::USAGE
    end
    private_class_method :dispatch

    def self.help(argv, table, environment)
      words = argv.drop(1)
      return list(argv, table, environment) if argv.one? || words.all? { |word| %w[--json --help -h].include?(word) }

      dispatch([*words, "--help"], table, environment) do
        "plastic: no command #{words.join(" ").inspect}; plastic help lists them"
      end
    end
    private_class_method :help

    # The shipped commands, one row each, as lines or as one document with --json.
    def self.list(argv, table, environment)
      output = printer(argv).new(out: environment.out, err: environment.err)
      table.each { |name, (_, summary)| output.row(name, summary) }
      output.flush
      Command::OK
    end

    def self.printer(argv) = argv.include?("--json") ? JsonOutput : TextOutput
    private_class_method :printer
  end
end
