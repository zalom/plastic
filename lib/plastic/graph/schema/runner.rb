# frozen_string_literal: true

require_relative "home_migration"
require_relative "store_migration"

module Plastic
  module Graph
    # Brings the databases of a home to the newest version of their sequences. The install and the update run it, and
    # nothing else does. A store that stays behind does not stop the run: the others go on.
    class SchemaRunner
      # `migrated` names the stores that moved; `failed` maps each store that stayed behind to the reason.
      Report = Data.define(:migrated, :failed) do
        def self.of(results)
          grouped = results.group_by { |_slug, outcome| outcome.is_a?(String) ? :failed : outcome }
          new(migrated: grouped.fetch(:migrated, []).map(&:first), failed: grouped.fetch(:failed, []).to_h)
        end
      end

      # `only` names one store to migrate; the home database is checked either way.
      def initialize(home:, now:, only: nil)
        @home = home
        @only = only
        @now = now
      end

      def call
        results = store_slugs.to_h { |slug| [slug, StoreMigration.new(@home, slug, @now).call] }
        results["home"] = HomeMigration.new(@home, @now).call
        Report.of(results)
      end

      private

      def store_slugs
        folder = File.join(@home, "stores")
        File.directory?(folder) ? Dir.children(folder).sort.select { |name| File.directory?(File.join(folder, name)) && (@only.nil? || name == @only) } : []
      end
    end
  end
end
