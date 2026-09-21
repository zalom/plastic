# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"

# `plastic intent new` - scaffolds a new intent (still `new-intent`, run
# through Legacy) and folds it into INDEX.md (`index-projection --write`).
# There is no id yet, so this is the one intent command that does not resolve
# one through Scope; it works on the store directly.
module Plastic
  class CLI
    module Commands
      class IntentNew < Command
        USAGE_LINE = 'plastic intent new "LINE" --slug SLUG [--parent ID] [--sources IDS] [--tags TAGS] [--json]'

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          raise Usage, "the one-line intent statement is required" if line.to_s.empty?
          raise Usage, "--slug is required" if options[:slug].to_s.empty?

          status = legacy.run("new-intent", *new_intent_arguments)
          raise Failure, "new-intent exited #{status}" unless status.zero?

          status = legacy.run("index-projection", scope.root, "--write")
          raise Failure, "index-projection exited #{status}" unless status.zero?

          @output.next_step("plastic status", because: "the new intent's id is printed above")
        end

        private

        def line
          arguments.first
        end

        def switches(parser)
          parser.on("--slug SLUG") { |v| @options[:slug] = v }
          parser.on("--parent ID") { |v| @options[:parent] = v }
          parser.on("--sources IDS") { |v| @options[:sources] = v }
          parser.on("--tags TAGS") { |v| @options[:tags] = v }
        end

        def new_intent_arguments
          args = ["--store", scope.store, "--intent", line, "--slug", options[:slug]]
          args += ["--parent", options[:parent]] if options[:parent]
          args += ["--sources", options[:sources]] if options[:sources]
          args += ["--tags", options[:tags]] if options[:tags]
          args
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner)
        end
      end
    end
  end
end
