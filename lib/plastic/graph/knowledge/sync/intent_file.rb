# frozen_string_literal: true

require_relative "legacy_import"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # The front matter of an intent file, and the reason it cannot give a
        # row: a missing field, or an id that is not the folder's number.
        class IntentFile
          REQUIRED = %w[id intent created].freeze

          attr_reader :front

          def initialize(text, number)
            @number = number
            decoded = text.dup.force_encoding(Encoding::UTF_8)
            @front = decoded.valid_encoding? ? decoded[LegacyImport::FRONT_MATTER, 1].to_s.scan(LegacyImport::FIELD).to_h : {}
          end

          # Why no row can be read from the file, or nil.
          def problem = missing || wrong_id

          private

          def missing
            names = REQUIRED.select { |field| front[field].to_s.strip.empty? }.join(", ")
            "it has no #{names} in its front matter" unless names.empty?
          end

          def wrong_id
            id = front["id"]
            "its id #{id} is not the folder number #{@number}" unless id == @number
          end
        end
      end
    end
  end
end
