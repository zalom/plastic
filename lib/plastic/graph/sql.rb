# frozen_string_literal: true

require "json"
require_relative "../invalid"

module Plastic
  module Graph
    # The statements of the graph, built with named placeholders and bound values.
    module SQL
      # SQL text that goes into a statement as it is, never as a bound value.
      Raw = Data.define(:sql)

      # A statement and the values its placeholders take.
      Bound = Data.define(:sql, :values)

      # How a list of columns joins into a clause: the comparison and the separator.
      Join = Data.define(:operator, :separator)

      CONDITION = Join.new("IS", " AND ")
      ASSIGNMENT = Join.new("=", ", ")

      NAME = /[a-z_][a-z0-9_]*/
      PLACEHOLDER = /(?<!:):(#{NAME})\b/
      LARGEST_INTEGER = 2**63 - 1

      def self.name(identifier) = %("#{identifier.to_s.gsub('"', '""')}")

      def self.names(list) = list.map { |column| name(column) }.join(", ")

      # `a = excluded.a`, for the update of an upsert.
      def self.assignment(column)
        quoted = name(column)
        "#{quoted} = excluded.#{quoted}"
      end

      def self.assignments(columns) = columns.map { |column| assignment(column) }.join(", ")

      def self.placeholders(sql) = sql.scan(PLACEHOLDER).flatten.uniq.map(&:to_sym)

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

      def self.where(values, prefix) = pairs(values, CONDITION, prefix)

      def self.set(values, prefix) = pairs(values, ASSIGNMENT, prefix)

      def self.pairs(values, join, prefix)
        parts = values.map { |column, value| "#{name(column)} #{join.operator} #{operand(value, prefix, column)}" }
        Bound.new(parts.join(join.separator), prefixed(values.reject { |_column, value| raw?(value) }, prefix))
      end

      def self.operand(value, prefix, column) = raw?(value) ? value.sql : ":#{prefix}_#{column}"

      def self.raw?(value) = value.is_a?(Raw)

      def self.list(values, prefix)
        keyed = values.each_with_index.to_h { |value, index| [index, value] }
        Bound.new(keyed.keys.map { |index| ":#{prefix}_#{index}" }.join(", "), prefixed(keyed, prefix))
      end

      def self.tuple(columns, prefix)
        checked_columns(columns)
        keys = columns.keys
        placeholders = keys.map { |key| ":#{prefix}_#{key}" }
        Bound.new("(#{names(keys)}) VALUES (#{placeholders.join(", ")})", prefixed(columns, prefix))
      end

      # An INSERT of one row; `clause` is what follows the values, such as an upsert.
      def self.insert(table, row, clause = "")
        tuple = tuple(row, "v")
        Bound.new("INSERT INTO #{name(table)} #{tuple.sql}#{clause}", tuple.values)
      end

      def self.checked_columns(columns)
        columns.each do |key, value|
          reason = column_problem(key, value)
          raise Plastic::Invalid, "column #{key.inspect} #{reason}" if reason
        end
      end

      def self.column_problem(key, value)
        if !key.to_s.match?(/\A#{NAME}\z/)
          "is not a plain lowercase name"
        elsif raw?(value)
          "holds SQL text, not a value"
        end
      end

      def self.prefixed(values, prefix) = values.to_h { |key, value| [:"#{prefix}_#{key}", value] }

      # An UPDATE that moves a node between states: the row in `from` with
      # `intent_id`/`id` moves to `to`, with `set` merged in, and returns its id.
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
