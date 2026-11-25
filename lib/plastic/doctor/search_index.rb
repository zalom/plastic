# frozen_string_literal: true

require "shellwords"
require_relative "check"
require_relative "../graph"
require_relative "../scope"

module Plastic
  module Doctor
    # Whether the search rows of one store match its passages. It opens the
    # knowledge database only when the file exists, rebuilds the rows that
    # are out of step from the current documents, and makes no database.
    class SearchIndex
      OPEN = ->(home, slug) { Graph.open(home:, store: slug).retrieval }

      # The checks of the global store and of each project store.
      def self.checks(scope, opener: OPEN)
        slugs = [Scope::GLOBAL, *scope.projects.keys].uniq
        slugs.filter_map { |slug| new(scope.plastic_home, slug, opener:).check }
      end

      def initialize(home, slug, opener: OPEN)
        @home = home
        @slug = slug
        @opener = opener
      end

      def check
        return unless File.directory?(folder)
        return row("ok, no database in this store") unless File.file?(knowledge)

        guarded { judged(retrieval) }
      end

      private

      attr_reader :home, :slug, :opener

      def judged(retrieval)
        retrieval.search_index_report.fetch(:repairable) ? mended(retrieval) : row("ok, in step")
      end

      def mended(retrieval)
        retrieval.repair
        row("ok, rebuilt")
      rescue Graph::Database::Error => error
        raise unless error.message.match?(/readonly/i)

        row("out of step, not rebuilt, the store cannot be written", "make #{folder} writable, then run plastic doctor again")
      end

      def guarded
        yield
      rescue Graph::Database::Error => error
        raise unless error.message.match?(/locked|busy|readonly/i)

        unchecked_row(error)
      end

      def unchecked_row(error)
        return row("not checked, the store cannot be written", "make #{folder} writable, then run plastic doctor again") if error.message.match?(/readonly/i)

        row("not checked, the database is held by another process", "stop the process that holds #{knowledge}, then run plastic doctor again")
      end

      def row(value, repair = nil) = Check.new("search index #{slug}:", value, repair)

      def retrieval = opener.call(home, slug)

      def folder = File.join(home, "stores", slug)

      def knowledge = File.join(folder, Graph::Schema.file(:knowledge))
    end
  end
end
