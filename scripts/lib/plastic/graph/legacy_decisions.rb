# frozen_string_literal: true

require_relative "legacy_decision_bullets"

module Plastic
  module Graph
    # Imports rulings and references from the original legacy document bytes.
    class LegacyDecisions
      RULING_ID = /\A\*{0,2}D(\d+)\b/

      def read_decisions(dirs, originals)
        dirs.map do |dir|
          main, spec = ["#{File.basename(dir)}.md", "spec.md"].map { |name| text_of(originals["#{dir}/#{name}"]) }
          bullets = [spec, main].map { |text| LegacyDecisionBullets.call(text) }.find(&:any?) || []
          { intent_id: File.basename(dir).split("--").first, rulings: assign_ruling_ids(bullets),
            source: front_matter_refs(main, "sources"), chain: front_matter_refs(main, "chain") }
        end
      end

      def text_of(bytes) = bytes.to_s.dup.force_encoding(Encoding::UTF_8)

      def write_decisions(databases, decisions, counts)
        decisions.each do |decision|
          intent_id = decision.fetch(:intent_id)
          write_rulings(databases, intent_id, decision.fetch(:rulings), counts)
          %i[source chain].each { |kind| write_links(databases, intent_id, decision.fetch(kind), kind.to_s, counts) }
        end
      end

      def assign_ruling_ids(bullets)
        taken = []
        bullets.map do |bullet|
          number = bullet[RULING_ID, 1].to_i
          number = (taken.max || 0) + 1 if number.zero? || taken.include?(number)
          taken << number
          ["D#{number}", bullet]
        end
      end

      def write_rulings(databases, intent_id, bullets, counts)
        database = databases.fetch(:knowledge)
        bullets.each do |id, text|
          row = { intent_id:, id:, text:, supersedes: nil, at: Plastic.now, session_id: @session }
          database.transaction { |batch| batch.put(:rulings, row, statement: :insert) }
          counts[:rulings] += 1
        end
      end

      def front_matter_refs(text, key)
        line = text[/^#{Regexp.escape(key)}:\s*(\[.*\])\s*$/, 1]
        line ? line.scan(/"([^"]+)"/).flatten : []
      end

      def write_links(databases, intent_id, refs, kind, counts)
        database = databases.fetch(:knowledge)
        refs.each do |ref|
          row = { from_ref: intent_id, to_ref: ref, kind:, at: Plastic.now }
          database.transaction { |batch| batch.put(:links, row, statement: :insert) }
          counts[:links] += 1
        end
      end
    end
  end
end
