# frozen_string_literal: true

require_relative "../../clock"

module Plastic
  module Graph
    module Work
      # A short digest of one project, so a session starts with the project in
      # its context: where its store and repository are, which files say what it
      # is for, the work in play and the last deliveries. It names paths in place
      # of their contents, so the digest stays small.
      class ProjectDigest
        DELIVERED = 3
        READ = %w[AGENTS.md README.md].freeze
        ARCHITECTURE = "a coding project: check its architecture map with a tool such as Enola"

        # `retrieval` is nil when the store folder is missing; `repo` is nil when no path is registered.
        def initialize(slug:, store:, repo:, retrieval:)
          @slug = slug
          @store = store
          @repo = repo
          @retrieval = retrieval
        end

        def rows = [*place_rows, *read_rows, *work_rows, *architecture_rows, ["search:", "plastic search TERMS --source-project #{@slug}"]]

        private

        def place_rows = [["project:", @slug], ["store:", marked(@store, @retrieval)], ["repo:", repo_text]]

        def repo_text = @repo ? marked(@repo, File.directory?(@repo)) : "none registered"

        def marked(path, present) = present ? path : "#{path} (missing)"

        def read_rows
          return [] unless @repo

          READ.map { |name| File.join(@repo, name) }.select { |path| File.file?(path) }.map { |path| ["read:", path] }
        end

        def architecture_rows = (@repo && File.exist?(File.join(@repo, ".git"))) ? [["architecture:", ARCHITECTURE]] : []

        def work_rows
          return [] unless @retrieval

          intents = @retrieval.intents
          [*in_play_rows(intents), waiting_row(intents), *delivered_rows(intents)]
        end

        def in_play_rows(intents)
          started = intents.select { |intent| intent.status == "in_progress" }
          started.empty? ? [["in play:", "none"]] : started.map { |intent| ["in play:", intent.label] }
        end

        def waiting_row(intents)
          count = intents.count { |intent| intent.status == "open" }
          ["waiting:", "#{count} open #{(count == 1) ? "intent" : "intents"}; plastic status --project #{@slug} lists them"]
        end

        # The day a stored time falls on here; an older date-only value shows as it is.
        def day(stamp) = Plastic.local_day(stamp) || stamp.to_s[0, 10]

        def delivered_rows(intents)
          done = intents.select { |intent| intent.status == "done" && intent.closed_at }
          done.max_by(DELIVERED) { |intent| Plastic.utc(intent.closed_at).to_s }
            .map { |intent| ["delivered:", "#{day(intent.closed_at)} #{intent.label}"] }
        end
      end
    end
  end
end
