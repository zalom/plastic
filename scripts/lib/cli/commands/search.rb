# frozen_string_literal: true

require_relative "../command"
require_relative "../../search_index"
require_relative "../../rlm/query"

module Plastic
  class CLI
    module Commands
      class Search < Command
        USAGE_LINE = "plastic search TERMS [--ask] [--project SLUG] [--limit N] [--json]"
        DEFAULT_LIMIT = 10

        def call
          raise Usage, "TERMS is missing" if arguments.empty?
          raise Failure, "no index at #{database}; run plastic index" unless File.file?(database)

          rows = options[:ask] ? RLM::Query.new(RLM::Probe.new(corpus, limit: limit)).call(arguments.join(" ")) : found(arguments, limit)
          rows.each { |row| @output.row(row["path"], row["excerpt"].gsub(/\s+/, " ").strip) }
          @output.row("result", "no match") if rows.empty?
          @output.next_step("plastic index", because: "the index was built #{File.mtime(database).strftime("%Y-%m-%d %H:%M")}; rebuild it when the stores have changed")
        rescue Sqlite::Error => e
          raise Failure, e.message
        end

        private

        def switches(parser)
          parser.on("--ask") { @options[:ask] = true }
          parser.on("--project SLUG") { |slug| @options[:project] = slug }
          parser.on("--limit N", Integer) { |limit| @options[:limit] = limit }
        end

        def limit
          options[:limit] || DEFAULT_LIMIT
        end

        def found(terms, count)
          SearchIndex.search(scope.plastic_home, terms, limit: count, prefix: prefix)
        end

        def corpus
          RLM::Corpus.new(method(:found))
        end

        def database
          SearchIndex.path(scope.plastic_home)
        end

        def prefix
          return "" unless options[:project]

          (scope.slug == Scope::GLOBAL) ? "store/" : "projects/#{scope.slug}/"
        end
      end
    end
  end
end
