# frozen_string_literal: true

module Plastic
  module Workflows
    # The code worktree of an intent: the repository the store's project names
    # in projects.yml, the folder under its .claude/worktrees and the branch.
    Worktree = Data.define(:repo, :path, :branch) do
      # Nil when the store's project names no repository, such as the global store.
      def self.of(scope, intent)
        repo = scope&.projects&.fetch(scope.slug, nil).to_s
        return nil if repo.empty?

        name = "#{intent.intent_id}--#{intent.slug}"
        new(repo:, path: File.join(repo, ".claude", "worktrees", name), branch: "plastic/#{name}")
      end
    end
  end
end
