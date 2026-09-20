# encoding: UTF-8
# frozen_string_literal: true

require "optparse"
require_relative "output"
require_relative "scope"

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

      def call
        raise NoMethodError, "#{self.class} must define call"
      end

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
