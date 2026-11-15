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

      def found = (PLACES.filter_map { |place| on_disk(place) }.first if folder)

      def folder = (@worktree.path if @worktree&.then { |tree| File.directory?(tree.path) }) || @worktree&.repo

      # The place as the disk spells it, nil when a name on the way is missing or the end is no template.
      def on_disk(place)
        names = spelled(place.chomp("/").split("/"), folder)
        return unless names

        folder_place = place.end_with?("/")
        path = File.join(folder, *names)
        return unless folder_place ? holds_markdown?(path) : File.file?(path)

        folder_place ? "#{names.join("/")}/" : names.join("/")
      end

      # The names on the disk that match `wanted` without regard to case, nil when one is missing.
      def spelled(wanted, at)
        return [] if wanted.empty?

        name = Dir.children(at).find { |each| each.casecmp?(wanted.first) } if File.directory?(at)
        rest = name && spelled(wanted.drop(1), File.join(at, name))
        [name, *rest] if rest
      end

      def holds_markdown?(path) = File.directory?(path) && Dir.children(path).any? { |each| each.downcase.end_with?(".md") && File.file?(File.join(path, each)) }
    end
  end
end
