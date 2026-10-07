# frozen_string_literal: true

require_relative "cli/command"
require_relative "cli/table"
require_relative "cli/listing"
require_relative "cli/topics"

module Plastic
  # The command line of the kernel: finds the command that argv names in
  # TABLE, loads its class, and hands it the call.
  class CLI
    TOPICS = File.expand_path("../../../docs/help", __dir__)

    # The command the words name: the longest table entry that starts argv,
    # so `intent lock status` wins over `intent lock`.
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

    Context = Struct.new(:environment, :table, :topics) do
      def environment_and_table = [environment, table]

      def self.build(given) = new(environment: Command::Environment.current, table: TABLE, topics: TOPICS, **given)
    end

    # The whole of bin/plastic: find the command, hand it the rest of argv and
    # its own words. A hook reads its event from the environment's input;
    # other tools ignore it.
    def self.call(argv, **given)
      context = Context.build(given)
      dispatch(argv.empty? ? ["help"] : argv, context) do
        "plastic: no command #{argv.first(2).join(" ").inspect}; plastic help lists them"
      end
    end

    # The whole of bin/plastic: run a shipped command, list the shipped
    # commands for `plastic help`, and name a command that has no stage yet
    # instead of blaming the words the owner typed.
    def self.bin_call(argv, **given) = route(argv, Context.build(given))

    def self.route(argv, context)
      command = argv.first.to_s
      return list(argv, context) if command.empty? || %w[--help -h].include?(command)
      return help(argv, context) if command == "help"

      dispatch(argv, context) { "plastic #{argv.join(" ")} is not in this build yet; it lands with its stage" }
    end
    private_class_method :route

    # Runs the command the words name, or prints the block's line and exits 2.
    def self.dispatch(argv, context)
      environment, table = context.environment_and_table
      name = find(argv, table)
      return tool(name, table).call(argv.drop(name.split.size), words: name, environment:) if name

      environment.err.puts yield
      Command::USAGE
    end
    private_class_method :dispatch

    def self.help(argv, context)
      words = argv.drop(1)
      return list(argv, context) if argv.one? || words.all? { |word| %w[--json --help -h].include?(word) }

      topic_or_help(words, context)
    end
    private_class_method :help

    def self.topic_or_help(words, context)
      text = Topics.new(context.topics, context.table).read(words)
      return print_topic(text, context) if text

      dispatch([*words, "--help"], context) { "plastic: no command #{words.join(" ").inspect}; plastic help lists them" }
    end
    private_class_method :topic_or_help

    def self.print_topic(text, context)
      context.environment.out.print text
      Command::OK
    end
    private_class_method :print_topic

    def self.list(argv, context) = Listing.new(*context.environment_and_table).call(argv)
    private_class_method :list
  end
end
