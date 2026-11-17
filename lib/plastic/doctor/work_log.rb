# frozen_string_literal: true

require_relative "check"
require_relative "../graph"
require_relative "../cli/scope"

module Plastic
  module Doctor
    # Whether each intent of one store has the work log lines its rows call for. It adds a line a
    # failed write left out, opens no store that has no work database, and makes no database.
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

        added = repaired
        row(if added.zero?
          "ok, every intent has its lines"
        else
          "ok, added #{added} missing #{(added == 1) ? "line" : "lines"}"
        end)
      end

      private

      attr_reader :home, :slug, :opener

      def repaired
        graphs = opener.call(home, slug)
        graphs.retrieval.intents.sum { |intent| graphs.work.repair_log(intent.intent_id) }
      end

      def row(value) = Check.new("work log #{slug}:", value, nil)

      def folder = File.join(home, "stores", slug)
    end
  end
end
