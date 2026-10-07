# frozen_string_literal: true

require "shellwords"

module Plastic
  module Workflows
    # The code worktree of an intent: the repository the store's project names
    # in projects.yml, the folder under its .claude/worktrees and the branch.
    # Plastic runs no version control command, so `command` is the line an
    # agent runs to add it.
    Worktree = Data.define(:repo, :path, :branch) do
      # Nil when the store's project names no repository, such as the global store.
      def self.of(scope, intent)
        repo = scope&.projects&.fetch(scope.slug, nil).to_s
        return nil if repo.empty?

        name = "#{intent.intent_id}--#{intent.slug}"
        new(repo:, path: File.join(repo, ".claude", "worktrees", name), branch: "plastic/#{name}")
      end

      def command = "git -C #{Shellwords.escape(repo)} worktree add #{Shellwords.escape(path)} -b #{Shellwords.escape(branch)}"

      def present? = File.directory?(path)
    end
  end
end
