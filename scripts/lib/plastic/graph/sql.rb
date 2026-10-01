# frozen_string_literal: true

require "json"

module Plastic
  module Graph
    # SQL text built from Ruby values: literals, quoted names, bound
    # parameters and the column list of an insert.
    module SQL
      # Bytes that go in as a BLOB literal, such as a kept file.
      Bytes = Data.define(:data)

      # SQL text kept as it stands, such as `retries + 1`, never quoted.
      Raw = Data.define(:sql)

      # A value as an SQL literal. Hashes and arrays are stored as JSON text.
      def self.literal(value)
        case value
        in nil then "NULL"
        in true then "1"
        in false then "0"
        in Integer | Float => number then number.to_s
        in Bytes | Raw => wrapped then wrapped_literal(wrapped)
        in Hash | Array then literal(JSON.generate(value))
        else "'#{value.to_s.gsub("'", "''")}'"
        end
      end

      # A value that carries its own SQL text: bytes as a BLOB literal, raw as itself.
      def self.wrapped_literal(wrapped)
        case wrapped
        in Bytes then "X'#{wrapped.data.unpack1("H*")}'"
        in Raw then wrapped.sql
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

      # `a = 1, b = 'x'`, for the SET clause of a guarded UPDATE.
      def self.set(values) = values.map { |column, value| "#{name(column)} = #{literal(value)}" }.join(", ")

      # `'a', 'b'`, for a SQL IN (...) list.
      def self.list(values) = values.map { |value| literal(value) }.join(", ")

      # The columns and values of an insert: `(a, b) VALUES (1, 2)`.
      def self.tuple(columns)
        names = columns.keys.map { |key| name(key) }
        values = columns.values.map { |value| literal(value) }
        "(#{names.join(", ")}) VALUES (#{values.join(", ")})"
      end
    end
  end
end
