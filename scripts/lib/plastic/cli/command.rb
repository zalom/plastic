# frozen_string_literal: true

require "optparse"
# Output prints the result lines; Scope finds the store a call works on;
# Parser reads argv.
require_relative "output"
require_relative "scope"
require_relative "parser"
require_relative "table"
require_relative "../invalid"

module Plastic
  class CLI
    # The boundary and the base of every tool: parse argv, run, print, exit
    # 0, 1, 2 or 3. Every command describes itself, so the harness can read
    # what a tool takes and which graph it reads and writes. The harness
    # decides when to call a tool; Plastic only describes it.
    class Command
      OK = 0
      FAILED = 1
      USAGE = 2
      REFUSED = 3

      Usage = Class.new(StandardError)

      # A gate stopped the call. Each error prints its own line and names its
      # exit code: 3 when the owner holds the step, 1 when the agent can fix it.
      class Refusal < StandardError
        def exit_code = REFUSED

        def report(output) = output.refused(message)
      end

      class Failure < StandardError
        def exit_code = FAILED

        def report(output) = output.failed(message)
      end

      GRAPHS = %i[work knowledge retrieval references].freeze

      # The first of these that is set names the calling session. Claude Code
      # sets the second; any harness may set the first.
      SESSION_VARIABLES = %w[PLASTIC_SESSION CLAUDE_CODE_SESSION_ID].freeze

      Argument = Data.define(:name, :label, :text, :rest, :optional)
      Option = Data.define(:name, :switch, :text, :default)

      # Where a call runs: the variables, stdin, the home and the working
      # directory. A test passes its own; bin/plastic passes the process's.
      Environment = Data.define(:env, :input, :home, :directory) do
        def self.current = new(env: ENV, input: $stdin, home: Dir.home, directory: Dir.pwd)
      end

      # What `plastic help --json` prints for one tool. The summary lives in
      # TABLE only, so `plastic help` lists tools without loading any of them.
      Description = Data.define(:name, :summary, :usage, :subject, :arguments,
        :options, :reads, :writes)

      class << self
        # The arguments that name the thing a call works on, such as the
        # intent id and the node id. A tool that writes keeps one open routine run per
        # subject (see RoutineRun).
        def subject(*names)
          names.any? ? @subject = names : @subject
        end

        def argument(name, label, text, rest: false, optional: false)
          arguments << Argument.new(name, label, text, rest, optional)
        end

        def option(name, switch, text, default: nil)
          options << Option.new(name, switch, text, default)
        end

        # Which graphs the tool reads or writes. Every read goes through the
        # retrieval graph; `reads :work` names the records it reads.
        def reads(*graphs) = graphs_for(:@reads, graphs)
        def writes(*graphs) = graphs_for(:@writes, graphs)

        def arguments = (@arguments ||= [])
        def options = (@options ||= [])

        # The first words TABLE gives this class. A class that runs under
        # several names, such as Group, is told its words by CLI.call.
        def tool_name
          TABLE.find { |_name, (klass, _summary)| klass == name.delete_prefix("Plastic::") }&.first
        end

        def usage_line(name = tool_name)
          parts = arguments.map { |a| a.optional ? "[#{a.label}]" : a.label }
          parts += options.map { |o| "[#{o.switch}]" }
          ["plastic", name, *parts].join(" ")
        end

        def describe(name = tool_name)
          Description.new(name:, summary: TABLE.dig(name, 1),
            usage: usage_line(name), subject:, arguments: arguments.map(&:to_h),
            options: options.map(&:to_h), reads: reads, writes: writes)
        end

        def call(...)
          command = new(...)
          command.run
        rescue OptionParser::ParseError, Scope::UnknownProject, Usage => e
          command.output.usage(e.message, command.usage_line)
          USAGE
        rescue Refusal, Failure => e
          command.flush unless command.output.json?
          e.report(command.output)
          e.exit_code
        end

        private

        def graphs_for(ivar, graphs)
          unknown = graphs - GRAPHS
          raise Plastic::Invalid, "#{name}: unknown graph #{unknown.join(", ")}" if unknown.any?

          list = instance_variable_get(ivar) || instance_variable_set(ivar, [])
          list.concat(graphs)
        end
      end

      attr_reader :output, :exit_code

      # `words` are the words that named this call, such as "intent end".
      def initialize(argv, out:, err:, words: self.class.tool_name, environment: Environment.current)
        @argv = argv.dup
        @words = words
        @environment = environment
        @exit_code = OK
        @output = Output.new(out:, err:, json: @argv.include?("--json"))
      end

      # The whole of one call: check the store, do the work, print.
      def run
        scope.slug if @argv.grep(/\A--project(?:=|$)/).any?
        call
        flush
        exit_code
      end

      def call
        raise NoMethodError, "#{self.class} must define call"
      end

      def usage_line = self.class.usage_line(words)

      # The rows go out before any error line, so a failed call still says
      # what it wrote.
      def flush
        @output.project = scope.slug
        @output.flush(json: parsed[:json])
        self
      end

      private

      attr_reader :words

      def parsed
        @parsed ||= Parser.new(arguments: self.class.arguments, options: self.class.options, banner: usage_line)
          .parse(@argv)
      end

      def blank?(value) = value.nil? || value.strip.empty?

      def session = SESSION_VARIABLES.lazy.filter_map { |name| @environment.env[name] unless blank?(@environment.env[name]) }.first

      # Which store the call works on: --project, then the working directory,
      # then the global store.
      def scope
        @scope ||= Scope.new(env: @environment.env, home: @environment.home, slug: parsed[:project],
          directory: @environment.directory)
      end

      # The graphs of the store the call works on, opened once.
      def graphs = (@graphs ||= Graph.open(home: scope.plastic_home, store: scope.slug))
    end
  end
end
