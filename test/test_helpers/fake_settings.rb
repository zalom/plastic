# frozen_string_literal: true

module Plastic
  class TestCase
    # The settings a call is given, held in memory: the values by dotted key, the problem and the
    # line the store reports, and every call to set and every harness asked for.
    class FakeSettings
      Store = Struct.new(:problem, :print_once)

      class Values
        def initialize(values, written)
          @values = values
          @written = written
        end

        def flag(path, default:) = @values.fetch(path.join("."), default)

        def choice(path, default:, allowed:)
          value = @values.fetch(path.join("."), default)
          allowed.include?(value) ? value : default
        end

        def source_projects = @values.fetch("search.source_projects", "").to_s.split(",")

        def entries = @values

        def overrides = @values.each_with_object({}) { |(key, value), tree| Plastic::Config::Rows.insert(tree, key, value) }

        def set(key, value) = @written[key] = value
      end

      attr_reader :written, :harnesses

      def initialize(values: {}, problem: nil, print_once: nil)
        @values = values
        @store = Store.new(problem, print_once)
        @written = {}
        @harnesses = []
      end

      def config(harness: nil)
        @harnesses << harness
        Values.new(@values, @written)
      end

      attr_reader :store
    end
  end
end
