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

      def self.call(...)
        command = new(...)
        command.validate_scope
        command.call
        command.flush
        OK
      rescue OptionParser::ParseError, Scope::UnknownProject, Usage => e
        command.output.usage(e.message, self::USAGE_LINE)
        USAGE
      rescue Refusal => e
        command.output.refused(e.message)
        REFUSED
      rescue Failure => e
        command.output.failed(e.message)
        FAILED
      end

      attr_reader :output

      def initialize(argv, out:, err:, env: ENV, home: Dir.home, directory: Dir.pwd)
        @argv = argv.dup
        @env = env
        @home = home
        @directory = directory
        @output = Output.new(out: out, err: err, json: @argv.include?("--json"))
      end

      def call
        raise NoMethodError, "#{self.class} must define call"
      end

      def validate_scope
        scope.slug if @argv.grep(/\A--project(?:=|$)/).any?
      end

      def flush
        @output.project = scope.slug
        @output.flush(json: options[:json])
      end

      private

      def options
        return @options if @options

        @options = {}
        parser.parse!(@argv)
        @options
      end

      def arguments
        options
        @argv
      end

      def parser
        @parser ||= OptionParser.new do |o|
          o.banner = self.class::USAGE_LINE
          o.on("--json") { @options[:json] = true }
          o.on("--project SLUG") { |slug| @options[:project] = slug }
          switches(o)
        end
      end

      def switches(_parser)
        nil
      end

      def scope
        @scope ||= Scope.new(env: @env, home: @home, slug: options[:project], directory: @directory)
      end
    end
  end
end
