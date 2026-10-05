# frozen_string_literal: true

require_relative "writer"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # Publishes a complete backup with its metadata row, or removes both.
        class Publisher
          def initialize(home_db, home, session: nil, writer: Writer.new(home, session:))
            @home_db = home_db
            @writer = writer
          end

          def call
            staged = @writer.stage
            publish(staged)
          rescue
            @writer.discard(staged) if defined?(staged) && staged
            raise
          end

          private

          def publish(staged)
            @home_db.transaction { |batch| batch.put(:backups, @writer.publish(staged), statement: :insert) }
            staged.row
          end
        end
      end
    end
  end
end
