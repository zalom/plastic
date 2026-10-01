# frozen_string_literal: true

require "json"

module Plastic
  module Graph
    # SQL text built from Ruby values: literals, quoted names, bound
    # parameters and the column list of an insert.
    module SQL
      # Bytes that go in as a BLOB literal, such as a kept file.
      Bytes = Data.define(:data)

      # A value as an SQL literal. Hashes and arrays are stored as JSON text.
      def self.literal(value)
        case value
        in nil then "NULL"
        in true then "1"
        in false then "0"
        in Integer | Float => number then number.to_s
        in Bytes then "X'#{value.data.unpack1("H*")}'"
        in Hash | Array then literal(JSON.generate(value))
        else "'#{value.to_s.gsub("'", "''")}'"
        end
      end

      def self.name(identifier) = %("#{identifier.to_s.gsub('"', '""')}")

      # `:name` in the SQL takes the value of `name`; a name with no value,
      # or a Postgres-style cast such as ::text, stays as it is.
      def self.bind(sql, values)
        return sql if values.empty?

        sql.gsub(/(?<!:):([a-z_][a-z0-9_]*)\b/) do
          key = Regexp.last_match(1).to_sym
          values.key?(key) ? literal(values[key]) : Regexp.last_match(0)
        end
      end

      def self.names(list) = list.map { |column| name(column) }.join(", ")

      # `a = excluded.a`, for the update of an upsert.
      def self.assignment(column)
        quoted = name(column)
        "#{quoted} = excluded.#{quoted}"
      end

      # `a IS 1 AND b IS 'x'`: IS matches a NULL as well.
      def self.where(values) = values.map { |column, value| "#{name(column)} IS #{literal(value)}" }.join(" AND ")

      # The columns and values of an insert: `(a, b) VALUES (1, 2)`.
      def self.tuple(columns)
        names = columns.keys.map { |key| name(key) }
        values = columns.values.map { |value| literal(value) }
        "(#{names.join(", ")}) VALUES (#{values.join(", ")})"
      end
    end
  end
end
