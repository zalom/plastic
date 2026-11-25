# frozen_string_literal: true

module Plastic
  module Graph
    # Deletes each stored ruling whose whole text is three dots, a placeholder an agent wrote by mistake, with every link
    # that names it. It keeps no copy in legacy.db, and its down removes the version alone. Docs: docs/contributing/MIGRATIONS.md.
    class PlaceholderRulings
      VERSION = "20261125100000"
      REFS = "SELECT intent_id || '/' || id FROM main.rulings WHERE text = '...'"
      COUNT = "SELECT COUNT(*) AS count FROM main.rulings WHERE text = '...'"
      DELETES = ["DELETE FROM main.links WHERE from_ref IN (#{REFS}) OR to_ref IN (#{REFS})", "DELETE FROM main.rulings WHERE text = '...'"].freeze

      # The number of rulings it deleted.
      Result = Data.define(:deleted) do
        def line(slug)
          return if deleted.zero?

          one = deleted == 1
          "migrate: #{slug} deleted #{deleted} #{one ? "ruling" : "rulings"} whose whole text is ..., #{one ? "a placeholder" : "placeholders"} " \
            "an agent wrote by mistake, with no copy and no undo"
        end
      end

      # `keep` is the keep of the data step; this step keeps nothing, since a placeholder is a mistake.
      def initialize(connection, _root, _selection, keep:)
        @connection = connection
        @keep = keep
      end

      def call
        deleted = @connection.read(COUNT).first.fetch("count")
        DELETES.each { |sql| @connection.execute(sql) }
        Result.new(deleted:)
      end
    end
  end
end
