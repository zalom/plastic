# frozen_string_literal: true

require_relative "worktree"

module Plastic
  module Workflows
    # The pull request template a repository carries, found by file name in the places GitHub and GitLab read.
    # It looks in the worktree of the intent when that folder exists and in the project repository otherwise.
    class PullRequestTemplate
      PLACES = %w[
        .github/pull_request_template.md
        pull_request_template.md
        docs/pull_request_template.md
        .github/PULL_REQUEST_TEMPLATE/
        .gitlab/merge_request_templates/
      ].freeze

      def self.fact(scope, intent) = new(Worktree.of(scope, intent)).fact

      def initialize(worktree)
        @worktree = worktree
      end

      def fact
        place = found
        place ? "The repository has a pull request template at #{place}; the description of the pull request follows it. " : ""
      end

      private

      def found = (PLACES.find { |place| present?(place) } if folder)

      def folder = (@worktree.path if @worktree&.then { |tree| File.directory?(tree.path) }) || @worktree&.repo

      def present?(place)
        path = File.join(folder, place)
        place.end_with?("/") ? File.directory?(path) && !Dir.empty?(path) : File.file?(path)
      end
    end
  end
end
