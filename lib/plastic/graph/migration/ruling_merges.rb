# frozen_string_literal: true

module Plastic
  module Graph
    # Merges each stored ruling that replaced another into the decision it replaced, now that a decision is rewritten in
    # place. It reads the supersedes links between rulings, follows each chain from the oldest ruling to the newest, gives
    # the oldest the text, the time and the session of the newest, and deletes the newer rulings and every link that names them. The old
    # texts stay in the ruled lines of the work log. It keeps nothing in legacy.db, and its down adds the column back
    # empty. Rows are the truth: a sync down writes the index of the store without the links. Docs: docs/contributing/MIGRATIONS.md.
    class RulingMerges
      VERSION = "20261125110000"
      LINKS = "SELECT from_ref, to_ref FROM main.links WHERE kind = 'supersedes' AND instr(from_ref, '/') > 0 AND instr(to_ref, '/') > 0"
      NEWEST = "SELECT text, at, session_id FROM main.rulings WHERE intent_id = :intent_id AND id = :id"
      REWRITE = "UPDATE main.rulings SET text = ?, at = ?, session_id = ? WHERE intent_id = ? AND id = ?"
      RULING = "DELETE FROM main.rulings WHERE intent_id = ? AND id = ?"
      NAMED = "DELETE FROM main.links WHERE from_ref = ? OR to_ref = ?"
      LINK = "DELETE FROM main.links WHERE kind = 'supersedes' AND from_ref = ? AND to_ref = ?"

      # The number of rulings it merged and of the decisions they replaced.
      Result = Data.define(:merged, :decisions) do
        def line(slug)
          return if merged.zero?

          one = merged == 1
          "migrate: #{slug} merged #{count(merged, "ruling")} that replaced another into the #{count(decisions, "decision")} " \
            "#{one ? "it" : "they"} replaced; run plastic store sync down --project #{slug} so the index of the store " \
            "drops #{one ? "its link" : "their links"}"
        end

        private

        def count(number, noun) = "#{number} #{(number == 1) ? noun : "#{noun}s"}"
      end

      # `keep` is the keep of the data step; this step keeps nothing, since the newest text of each decision stays.
      def initialize(connection, _root, _selection, keep:)
        @connection = connection
        @keep = keep
      end

      def call
        links = @connection.read(LINKS).map { |row| row.values_at("from_ref", "to_ref") }
        oldest = RulingMerges.oldest(links)
        merged = oldest.sum { |ref| merge_chain(ref, RulingMerges.chain(ref, links.to_h(&:reverse))) }
        links.each { |pair| @connection.execute(LINK, pair) }
        Result.new(merged:, decisions: oldest.size)
      end

      # The refs of the rulings that another replaced and that replaced none themselves, each the start of a chain.
      def self.oldest(links) = links.map(&:last).uniq - links.map(&:first)

      # The refs of the rulings that replaced `ref`, one after the other, oldest first.
      def self.chain(ref, newer)
        refs = []
        refs << ref while (ref = newer[ref]) && !refs.include?(ref)
        refs
      end

      private

      # Deletes the ruling of `ref` and every link that names it, so no link points at a ruling that is gone.
      def delete(ref)
        @connection.execute(RULING, ref.split("/", 2))
        @connection.execute(NAMED, [ref, ref])
      end

      # Gives the oldest ruling the text of the newest of `chain` and deletes the rulings of the chain.
      def merge_chain(ref, chain)
        newest = @connection.read(NEWEST, %i[intent_id id].zip(chain.last.split("/", 2)).to_h).first
        return 0 unless newest

        @connection.execute(REWRITE, [*newest.values_at("text", "at", "session_id"), *ref.split("/", 2)])
        chain.each { |newer| delete(newer) }
        chain.size
      end
    end
  end
end
