# frozen_string_literal: true

require_relative "intent_rows"

module Plastic
  module Graph
    module Work
      # A short digest of one project, so a session starts with the project in
      # its context: where its store and repository are, which files say what it
      # is for, the work in play with the passages the retrieval graph holds for it, and the last deliveries. It names paths in place
      # of their contents, so the digest stays small.
      class ProjectDigest
        READ = %w[AGENTS.md README.md].freeze
        ARCHITECTURE = "when the repository holds code, check its architecture map with an architecture mapping tool such as Enola"

        # `work` holds the rows of the work in play and is nil when the store cannot be read, and `note` then says why;
        # `repo` is nil when no path is registered.
        def initialize(slug:, store:, repo:, work:, note: nil)
          @slug = slug
          @store = note ? "#{store} (#{note})" : store
          @repo = repo
          @work = work
        end

        def rows = [*place_rows, *read_rows, *@work, *architecture_rows, ["search:", "plastic search TERMS --source-project #{@slug}"]]

        private

        def place_rows = [["project:", @slug], ["store:", @store], ["repo:", repo_text]]

        def repo_text
          repo = @repo
          return "none registered" unless repo

          File.directory?(repo) ? repo : "#{repo} (missing)"
        end

        def read_rows
          return [] unless @repo

          READ.map { |name| File.join(@repo, name) }.select { |path| File.file?(path) }.map { |path| ["read:", path] }
        end

        def architecture_rows = (@repo && File.directory?(@repo)) ? [["architecture:", ARCHITECTURE]] : []
      end
    end
  end
end
