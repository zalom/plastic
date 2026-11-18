# frozen_string_literal: true

module Plastic
  module Graph
    class Database
      # The check a database passes on its first use in a process: a file with a key is stamped and gated, a file
      # without one is built from its schema alone. Once it passes, it passes no more.
      class Check
        # The check of the file `file`, by the key of its schema when it is stamped; `layouts` maps each attached schema to its key.
        def self.for(schema, key, file, layouts) = key ? Gated.new(key, layouts, file) : Prepared.new(schema)

        attr_reader :key

        def initialize(key)
          @key = key
          @passed = false
        end

        def call(connection)
          return if @passed

          settle(connection)
          pass
        end

        def pass = (@passed = true)

        private

        def settle(_connection) = raise(NoMethodError, "#{self.class} does not settle a connection")
      end

      # A file with no stamp: it gets its schema.
      class Prepared < Check
        def initialize(schema)
          super(nil)
          @schema = schema
        end

        private

        def settle(connection) = Schema.prepare(connection, @schema)
      end

      # A stamped file: the schema gate lets it through, builds it or refuses it.
      class Gated < Check
        def initialize(key, layouts, file)
          super(key)
          @layouts = layouts
          @file = file
        end

        private

        def settle(connection) = SchemaGate.new(connection, layouts: @layouts, file: @file).call
      end
    end
  end
end
