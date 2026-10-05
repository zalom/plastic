# frozen_string_literal: true

module Plastic
  class CLI
    # A row value as plain lines: a hash prints as key: value lines, a nested
    # value is indented under its key, and an item of a list starts with a dash.
    module Readable
      INDENT = "  "

      def self.structured?(value) = value.is_a?(Hash) || (value.is_a?(Array) && value.any? { |item| nested?(item) })

      def self.nested?(item) = item.is_a?(Hash) || item.is_a?(Array)

      def self.lines(value)
        case value
        when Hash then value.flat_map { |key, item| pair(key, item) }
        when Array then value.flat_map { |item| listed(item) }
        else value.to_s.lines.map(&:chomp)
        end
      end

      def self.pair(key, item)
        return ["#{key}: #{item}"] if scalar?(item)

        ["#{key}:", *lines(item).map { |line| "#{INDENT}#{line}" }]
      end

      def self.scalar?(item) = !nested?(item) && !item.to_s.include?("\n")

      def self.listed(item)
        inner = lines(item)
        return ["- #{item}"] if inner.empty? && !nested?(item)

        inner.each_with_index.map { |line, index| "#{index.zero? ? "- " : INDENT}#{line}" }
      end
    end
  end
end
