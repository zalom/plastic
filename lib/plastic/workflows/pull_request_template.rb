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

      def self.child_named(at, wanted) = (Dir.children(at).find { |each| each.casecmp?(wanted) } if File.directory?(at))

      def self.spelled(wanted, at)
        names = []
        found = wanted.all? { |wanted_name| (name = child_named(File.join(at, *names), wanted_name)) && names << name }
        names if found
      end

      def self.holds_markdown?(path) = File.directory?(path) && Dir.children(path).any? { |each| each.downcase.end_with?(".md") && File.file?(File.join(path, each)) }

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

      def on_disk(place)
        names = PullRequestTemplate.spelled(place.chomp("/").split("/"), folder)
        return unless names

        folder_place = place.end_with?("/")
        path = File.join(folder, *names)
        return unless folder_place ? PullRequestTemplate.holds_markdown?(path) : File.file?(path)

        label = names.join("/")
        folder_place ? "#{label}/" : label
      end
    end
  end
end
