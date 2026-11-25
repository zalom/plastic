# frozen_string_literal: true

require_relative "../ruling"
require_relative "../ruling_order"
require_relative "numbers"

module Plastic
  module Graph
    module Knowledge
      class Ruling
        # Writes one intent's rulings: a new decision under the next whole number, an addition under the next number of
        # its decision, or a rewrite of a decision, which replaces its text and removes its additions with their links. A
        # text that begins with a label of its own id, such as "D3: Ship it", is stored without it.
        class Writer
          # A label of `id`: copies of the id with spaces between, then a colon, a period before a space or any dash,
          # or a space before a capital letter, a backtick, a quote or a bracket. A list sign or another id after it,
          # or a range word, which is lowercase, leaves the text alone, such as "D1 through D8 are binding".
          def self.label(id)
            own = Regexp.escape(id)
            /\A(?:#{own}\s+)*#{own}(?:\s*(?::|\.(?=\s)|[-–—])\s*|\s+(?=[A-Z`"'(\[]))(?=\S)(?![-–—.:,\/])(?!(?!#{own}\b)D\d)/
          end

          # The text without its leading labels of `id`.
          def self.own_text(text, id)
            stripped = text.sub(label(id), "")
            (stripped == text) ? text : own_text(stripped, id)
          end

          # Writes the rewritten row of a decision and removes each of its additions with every link that names it.
          def self.replace(batch, row, additions)
            batch.put(:rulings, row)
            additions.each { |addition| remove(batch, addition) }
          end

          def self.remove(batch, addition)
            ref = addition.ref
            batch.remove(:rulings, intent_id: addition.intent_id, id: addition.id)
            batch.remove(:links, from_ref: ref)
            batch.remove(:links, to_ref: ref)
          end

          def initialize(databases, retrieval, clock:, session: nil)
            @databases = databases
            @retrieval = retrieval
            @session = session
            @clock = clock
          end

          # Returns the ruling written, or nil when `adds` or `rewrites` names no whole decision of the intent.
          def add_ruling(intent_id:, text:, adds: nil, rewrites: nil)
            named = adds || rewrites
            target = named && whole_ruling(intent_id, named.delete_prefix("#{intent_id}/"))
            return nil if named && !target
            return rewrite(target, text) if rewrites

            numbers = numbers(intent_id)
            write_new(intent_id, text, target ? numbers.next_addition(target.id) : numbers.next_whole)
          end

          private

          def write_new(intent_id, text, id)
            ruling = Ruling.new(intent_id:, id:, text: Writer.own_text(text, id), at: stamp, session_id: @session, origin_id: nil)
            write { |batch| batch.insert_rows(rulings: ruling.to_h.except(:origin_id)) }
            find_ruling(intent_id, id)
          end

          def rewrite(target, text)
            intent_id, id = target.to_h.values_at(:intent_id, :id)
            additions = RulingOrder.additions(@retrieval.rulings(intent_id), id)
            row = target.with(text: Writer.own_text(text, id), at: stamp, session_id: @session).to_h.except(:origin_id)
            write { |batch| Writer.replace(batch, row, additions) }
            find_ruling(intent_id, id)
          end

          def whole_ruling(intent_id, id) = Numbers.whole?(id) ? find_ruling(intent_id, id) : nil

          def find_ruling(intent_id, id) = @retrieval.rulings(intent_id).find { |ruling| ruling.id == id }

          def write(&) = @databases.fetch(:store).transaction(&)

          def stamp = Plastic.timestamp(@clock.now)

          def numbers(intent_id) = Numbers.of(@retrieval.rulings(intent_id), @retrieval.structure.work_log(intent_id))
        end
      end
    end
  end
end
