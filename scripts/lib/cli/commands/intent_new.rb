# frozen_string_literal: true

require_relative "../command"
require_relative "../legacy"
require_relative "../../index_entry"

module Plastic
  class CLI
    module Commands
      class IntentNew < Command
        USAGE_LINE = 'plastic intent new "LINE" [--slug SLUG] [--parent ID] [--sources IDS] [--tags TAGS] [--json]'
        PASSED_THROUGH = %i[parent sources tags].freeze

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          raise Usage, "the one-line intent statement is required" if line.to_s.empty?

          status = Legacy.new(env: @env, runner: @runner, output: @output, json: options[:json]).run("new-intent", *new_intent_arguments)
          raise Failure, "new-intent exited #{status}" unless status.zero?

          IndexEntry.add_active(scope.index_path, dir_name: dir_name, title: line)
          @output.next_step("plastic intent spec #{id}", because: "a new intent has no specification yet")
        end

        private

        def line
          arguments.first
        end

        def slug
          options[:slug] || line.downcase.scan(/[a-z0-9]+/).first(5).join("-")
        end

        def dir_name
          newest = Dir.glob(File.join(scope.store, "*--#{slug}")).max_by { |path| File.mtime(path) }
          raise Failure, "new-intent made no directory for #{slug}" unless newest

          File.basename(newest)
        end

        def id
          dir_name.split("--").first
        end

        def switches(parser)
          parser.on("--slug SLUG") { |v| @options[:slug] = v }
          PASSED_THROUGH.each { |key| parser.on("--#{key} VALUE") { |v| @options[key] = v } }
        end

        def new_intent_arguments
          given = PASSED_THROUGH.select { |key| options[key] }
          ["--store", scope.store, "--intent", line, "--slug", slug] + given.flat_map { |key| ["--#{key}", options[key]] }
        end
      end
    end
  end
end
