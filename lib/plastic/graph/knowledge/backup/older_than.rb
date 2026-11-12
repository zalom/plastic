# frozen_string_literal: true

require "time"
require_relative "../backup"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # Reads the --older-than value. A date is local midnight of that day;
        # a full time with an offset is read as given. Anything else is refused.
        module OlderThan
          # The value is neither a date nor a full time with an offset.
          class Unreadable < StandardError; end

          DATE = /\A\d{4}-\d{2}-\d{2}\z/
          FULL = /\A\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:?\d{2})\z/

          def self.parse(text) = read(text) || raise(Unreadable, "cannot read #{text.inspect} as a date or a time with an offset")

          def self.read(text)
            return Time.new(*text.split("-").map(&:to_i)) if DATE.match?(text)

            Time.iso8601(text.sub(" ", "T")) if FULL.match?(text)
          rescue ArgumentError
            nil
          end
        end
      end
    end
  end
end
