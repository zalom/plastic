# frozen_string_literal: true

require_relative "check"
require_relative "../graph"
require_relative "../cli/scope"

module Plastic
  module Doctor
    # Whether each intent of one store has the work log lines its writes owe. It drains the lines a
    # write left pending after its commit, names each intent that gained lines, opens no store that has no work database, and makes no database.
    class WorkLog
      OPEN = ->(home, slug) { Graph.open(home:, store: slug) }

      def self.checks(scope, opener: OPEN)
        slugs = [CLI::Scope::GLOBAL, *scope.projects.keys].uniq
        slugs.filter_map { |slug| new(scope.plastic_home, slug, opener:).check }
      end

      def initialize(home, slug, opener: OPEN)
        @home = home
        @slug = slug
        @opener = opener
      end

      def check
        return unless File.directory?(folder)
        return row("ok, no database in this store") unless File.file?(File.join(folder, Graph::Schema.file(:work)))

        drained = drain
        row(drained.empty? ? "ok, every intent has its lines" : "ok, drained #{Graph::Schema.tally(:work_log, drained.values.sum)}: #{named(drained)}")
      end

      private

      attr_reader :home, :slug, :opener

      def drain = opener.call(home, slug).work.drain_logs.reject { |_, added| added.zero? }

      def named(drained) = drained.keys.map { |intent_id| "intent #{intent_id}" }.join(", ")

      def row(value) = Check.new("work log #{slug}:", value, nil)

      def folder = File.join(home, "stores", slug)
    end
  end
end
