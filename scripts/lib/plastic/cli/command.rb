# frozen_string_literal: true

require "optparse"
require_relative "command/usage"
require_relative "command/refusal"
require_relative "command/failure"
require_relative "command/environment"
require_relative "declarations"
require_relative "text_output"
require_relative "json_output"
require_relative "scope"
require_relative "parser"
require_relative "table"

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

      extend Declarations

      def self.call(...) = new(...).run

      attr_reader :exit_code

      # `words` are the words that named this call, such as "intent end".
      def initialize(argv, words: self.class.tool_name, environment: Environment.current)
        @argv = argv.dup
        @words = words
        @environment = environment
        @exit_code = OK
      end

      # Where the answer prints: one JSON document with --json, lines otherwise.
      def output
        @output ||= (@argv.include?("--json") ? JsonOutput : TextOutput).new(out: environment.out, err: environment.err)
      end

      # The whole of one call: check the store, do the work, print. A usage
      # error prints the usage line; a refusal or a failure prints its line
      # after the rows.
      def run
        answer
      rescue OptionParser::ParseError, Scope::UnknownProject, Usage => error
        misused(error)
      rescue Refusal, Failure => error
        stop(error)
      rescue Scope::BrokenProjects => error
        broken(error)
      end

      def answer
        check_scope
        call
        flush.exit_code
      end

      def call
        raise NoMethodError, "#{self.class} must define call"
      end

      def usage_line = self.class.usage_line(words)

      # The rows go out before any error line, so a failed call still says
      # what it wrote.
      def flush
        output.flush(scope.slug)
        self
      end

      private

      attr_reader :words, :environment

      # A named project must exist before any work runs.
      def check_scope = @argv.grep(/\A--project(?:=|$)/).any? && scope.slug

      def misused(error)
        output.usage(error.message, usage_line)
        USAGE
      end

      def stop(error)
        flush unless output.json?
        error.report(output)
        error.exit_code
      end

      def broken(error)
        output.flush unless output.json?
        output.failed(error.message)
        FAILED
      end

      def parsed
        tool = self.class
        @parsed ||= Parser.new(arguments: tool.arguments, options: tool.options, banner: usage_line).parse(@argv)
      end

      def session = environment.session

      # Which store the call works on: --project, then the working directory,
      # then the global store.
      def scope
        @scope ||= Scope.new(env: environment.env, home: environment.home, slug: parsed[:project],
          directory: environment.directory)
      end

      # The graphs of the store the call works on, opened once.
      def graphs = (@graphs ||= Graph.open(home: scope.plastic_home, store: scope.slug, session: environment.session))
    end
  end
end
