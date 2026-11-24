# frozen_string_literal: true

require_relative "../knowledge/ruling/writer"

module Plastic
  module Graph
    # Strips from each stored ruling the leading copies of its own id that an agent typed into the text, such as
    # "D3: Ship it", the way plastic intent rule strips them from a new ruling, and from the ruled line of the work log
    # that carries the ruling as "D3 D3: Ship it". The label was an agent's mistake, so it keeps no copy in legacy.db, and its
    # down removes the version alone. Rows are the truth: a sync down prints the stripped lines into the work.log files.
    # Docs: docs/contributing/MIGRATIONS.md.
    class RulingOwnIds
      VERSION = "20261124233000"
      RULINGS = "SELECT intent_id, id, text, origin_id FROM main.rulings WHERE substr(text, 1, length(id)) = id"
      RULING = "UPDATE main.rulings SET text = ? WHERE intent_id = ? AND id = ? AND origin_id = ?"
      LINES = "SELECT intent_id, position, origin_id, text FROM work.work_log WHERE kind = 'ruled'"
      LINE = "UPDATE work.work_log SET text = ? WHERE intent_id = ? AND position = ? AND origin_id = ?"
      # A ruled line: the ruling's id, one space, and the ruling's text.
      RULED = /\A(\S+) (.*)\z/m

      # The number of rulings and of work log lines it stripped.
      Result = Data.define(:rulings, :lines) do
        def line(slug)
          return if (rulings + lines).zero?

          "migrate: #{slug} stripped the leading own id from #{count(rulings, "ruling")} and #{count(lines, "work log line")}, an agent's " \
            "mistake with no copy and no undo; run plastic store sync down --project #{slug} so the printed work.log files carry them"
        end

        private

        def count(number, noun) = "#{number} #{(number == 1) ? noun : "#{noun}s"}"
      end

      # `keep` is the keep of the data step; this step keeps nothing, since the label is a mistake.
      def initialize(connection, _root, _selection, keep:)
        @connection = connection
        @keep = keep
      end

      def call = Result.new(rulings: rulings, lines: lines)

      private

      def rulings = rewrite(RULING, @connection.read(RULINGS)) { |row| own_text(row.fetch("text"), row.fetch("id")) }

      def lines
        rewrite(LINE, @connection.read(LINES)) do |row|
          id, text = RULED.match(row.fetch("text"))&.captures
          "#{id} #{own_text(text, id)}" if id
        end
      end

      # Writes the text the block makes of each row that it changes, and answers how many it changed.
      def rewrite(sql, rows)
        rows.count do |row|
          text = yield(row)
          next false if text.nil? || text == row.fetch("text")

          @connection.execute(sql, [text, row.fetch("intent_id"), row.fetch("id") { row.fetch("position") }, row.fetch("origin_id")])
        end
      end

      def own_text(text, id) = Knowledge::Ruling::Writer.own_text(text, id)
    end
  end
end
