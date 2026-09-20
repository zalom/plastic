# encoding: UTF-8
# frozen_string_literal: true

require "optparse"
require_relative "output"
require_relative "scope"

# Plastic::CLI::Command (intent 363) - the base every command sits on. It parses
# options with the standard OptionParser, owns the four exit codes, and takes
# its output stream, error stream, environment and home directory as arguments,
# so a test builds a command over a temporary store and no test reads the real
# ~/.plastic.
#
#   0 the command did its work
#   1 it tried and failed
#   2 the call was wrong
#   3 it refused, because the step belongs to the owner
#
# Exit code 3 is the one an agent must never retry with a flag. Raise Refusal
# for it and Failure for an ordinary failure; anything else is a bug and
# crashes, which is what a bug should do.
module Plastic
  class CLI
    class Command
      OK = 0
      FAILED = 1
      USAGE = 2
      REFUSED = 3

      Usage = Class.new(StandardError)
      Refusal = Class.new(StandardError)
      Failure = Class.new(StandardError)

      def initialize(argv, out:, err:, env: ENV, home: Dir.home, directory: Dir.pwd)
        @argv = argv.dup
        @env = env
        @home = home
        @directory = directory
        @options = {}
        @output = Output.new(out: out, err: err)
      end

      def run
        parse
        return help if @options[:help]

        call
        @output.flush(json: @options[:json])
        OK
      rescue OptionParser::ParseError, Scope::UnknownProject, Usage => e
        @output.usage(e.message, self.class::USAGE_LINE)
        USAGE
      rescue Refusal => e
        @output.refused(e.message)
        REFUSED
      rescue Failure => e
        @output.failed(e.message)
        FAILED
      end

      private

      def parse
        parser.parse!(@argv)
      end

      def help
        @output.row("usage", self.class::USAGE_LINE)
        @output.flush(json: @options[:json])
        OK
      end

      def parser
        @parser ||= OptionParser.new do |o|
          o.banner = self.class::USAGE_LINE
          o.on("--json") { @options[:json] = true }
          o.on("-h", "--help") { @options[:help] = true }
          options(o)
        end
      end

      def options(_parser)
        nil
      end

      def scope
        @scope ||= Scope.new(env: @env, home: @home, slug: @options[:project], directory: @directory)
      end
    end
  end
end
