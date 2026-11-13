# frozen_string_literal: true

require "json"
require_relative "../invalid"

module Plastic
  module Graph
    # SQL text with named placeholders, and the values that fill them. A value
    # never enters the text: it is converted here and bound by the gem.
    module SQL
      # SQL text kept as it stands, such as `retries + 1`, never a value.
      Raw = Data.define(:sql)

      # SQL text with placeholders, and the values the placeholders name.
      Bound = Data.define(:sql, :values)

      PLACEHOLDER = /(?<!:):([a-z_][a-z0-9_]*)\b/
      LARGEST_INTEGER = 2**63 - 1

      def self.name(identifier) = %("#{identifier.to_s.gsub('"', '""')}")

      def self.names(list) = list.map { |column| name(column) }.join(", ")

      # `a = excluded.a`, for the update of an upsert.
      def self.assignment(column)
        quoted = name(column)
        "#{quoted} = excluded.#{quoted}"
      end

      # The names a statement holds, in order of first appearance.
      def self.placeholders(sql) = sql.scan(PLACEHOLDER).flatten.uniq.map(&:to_sym)

      # The converted value of each name of the text. An extra key is dropped.
      def self.params(sql, values)
        placeholders(sql).to_h do |key|
          raise Plastic::Invalid, "no value for :#{key}" unless values.key?(key)

          [key, bindable(values.fetch(key))]
        end
      end

      def self.bindable(value)
        convert(value)
      rescue => error
        raise Plastic::Invalid, "a #{value.class} cannot be bound: #{error.message}"
      end

      # A value as the gem binds it. Hashes and arrays are stored as JSON text.
      def self.convert(value)
        case value
        in nil | Float | SQLite3::Blob then value
        in true then 1
        in false then 0
        in Integer then integer(value)
        in Hash | Array then JSON.generate(value)
        in String then text(value)
        else value.to_s
        end
      end

      def self.integer(value)
        raise RangeError, "out of range" unless value.abs <= LARGEST_INTEGER

        value
      end

      def self.text(value) = (value.encoding == Encoding::BINARY) ? value.dup.force_encoding(Encoding::UTF_8) : value

      # `a IS :m_a AND b IS :m_b`: IS matches a NULL as well.
      def self.where(values, prefix) = pairs(values, "IS", " AND ", prefix)

      # `a = :s_a, b = :s_b`, for the SET clause of a guarded UPDATE.
      def self.set(values, prefix) = pairs(values, "=", ", ", prefix)

      def self.pairs(values, operator, joiner, prefix)
        parts = values.map { |column, value| "#{name(column)} #{operator} #{value.is_a?(Raw) ? value.sql : ":#{prefix}_#{column}"}" }
        Bound.new(parts.join(joiner), prefixed(values.reject { |_column, value| value.is_a?(Raw) }, prefix))
      end

      # `:f_0, :f_1`, for a SQL IN (...) list.
      def self.list(values, prefix)
        keyed = values.each_with_index.to_h { |value, index| [index, value] }
        Bound.new(keyed.keys.map { |index| ":#{prefix}_#{index}" }.join(", "), prefixed(keyed, prefix))
      end

      # The columns and placeholders of an insert: `(a, b) VALUES (:v_a, :v_b)`.
      def self.tuple(columns, prefix)
        placeholders = columns.keys.map { |key| ":#{prefix}_#{key}" }
        Bound.new("(#{names(columns.keys)}) VALUES (#{placeholders.join(", ")})", prefixed(columns, prefix))
      end

      def self.prefixed(values, prefix) = values.to_h { |key, value| [:"#{prefix}_#{key}", value] }

      # An UPDATE that moves a node between states: the row in `from` with
      # `intent_id`/`id` moves to `to`, with `set` merged in, and returns its
      # id only when a row was found. The caller adds `intent_id`, `id` and `origin`.
      def self.move(to:, from:, set: {})
        assignments = set({ state: to, updated_at: Plastic.now }.merge(set), "s")
        states = list(from, "f")
        text = <<~SQL
          UPDATE nodes SET #{assignments.sql}
          WHERE intent_id = :intent_id AND id = :id AND origin_id = :origin AND state IN (#{states.sql})
          RETURNING id
        SQL
        Bound.new(text, assignments.values.merge(states.values))
      end
    end
  end
end
