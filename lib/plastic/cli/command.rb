# frozen_string_literal: true

require "forwardable"
require "optparse"
require_relative "command/environment"
require_relative "day_backup"
require_relative "wiring"
require_relative "command/help"
require_relative "command/invocation"
require_relative "command/settlement"
require_relative "command/workspace"
require_relative "declarations"
require_relative "../errors"
require_relative "../graph/missing_store"
require_relative "../graph/behind"
require_relative "text_output"
require_relative "json_output"
require_relative "../scope"
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
      extend Forwardable

      def self.call(...) = new(...).respond

      attr_reader :exit_code

      # `words` are the words that named this call, such as "intent end".
      def initialize(argv, words: tool.tool_name, environment: Environment.current)
        @call = Invocation.new(argv, words, tool)
        @workspace = Workspace.new(environment, -> { new_scope })
        @output = nil
        @exit_code = OK
      end

      # Where the answer prints: one JSON document with --json, lines otherwise.
      def output
        @output ||= (@call.json? ? JsonOutput : TextOutput).new(out: environment.out, err: environment.err)
      end

      # The whole of one call: check the store, do the work, print. A usage
      # error prints the usage line; a refusal or a failure prints its line
      # after the rows.
      def respond
        return help if @call.help?

        answer
      rescue OptionParser::ParseError, Scope::UnknownProject, Usage, Refused, Failed, Graph::MissingStore, Graph::OutOfStep => error
        settlement.settle(error)
      end

      def answer
        check_scope
        back_up_the_day
        call_and_renew
        flush.exit_code
      rescue Scope::BrokenProjects => error
        settlement.broken(error)
      end

      def call_and_renew
        call
      ensure
        renew_claims
      end

      def call
        raise NoMethodError, "#{self.class} must define call"
      end

      def usage_line = @call.usage_line

      def help
        Help.new(self.class, usage_line).lines.each { |line| output.raw(line) }
        output.flush.then { OK }
      end

      # The rows go out before any error line, so a failed call still says
      # what it wrote.
      def flush
        output.flush(scope.named_slug)
        self
      end

      private

      def_delegators :@call, :words, :argv, :parsed
      def_delegator :@workspace, :environment
      def_delegators :@workspace, :graphs, :settings, :renew_claims
      private :words, :environment, :argv, :parsed, :graphs, :settings, :renew_claims

      def tool = self.class

      def settlement = Settlement.new(output, usage_line, @workspace)

      # The start-of-day backups the call takes first, unless it is a dry run.
      def back_up_the_day = (DayBackup.new(environment).back_up(:begin_day) unless parsed[:dry_run])

      # A named project must exist before any work runs.
      def check_scope = @call.project_named? && scope.slug

      # Which store the call works on: --project, then the working directory,
      # then the global store.
      def scope = @workspace.scope

      def new_scope
        Scope.new(env: environment.env, home: environment.home, slug: parsed[:project], directory: environment.directory)
      end
    end
  end
end
