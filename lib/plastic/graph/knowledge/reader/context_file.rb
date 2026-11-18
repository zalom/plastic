# frozen_string_literal: true

require "json"
require_relative "../../../invalid"

module Plastic
  module Graph
    module Knowledge
      class Reader
        # A context.json read for an intent that holds no context and no discovery: the two rows it carries.
        class ContextFile
          TABLES = { "discovery" => :retrieval_discoveries, "context" => :retrieval_contexts }.freeze

          def initialize(text, intent_id, path)
            @text = text
            @intent_id = intent_id
            @path = path
          end

          # Why the file cannot be read, or nil when it can.
          def problem
            data
            nil
          rescue Invalid => error
            error.message
          end

          # The rows by table, one for each part the file holds.
          def rows(now)
            found = data
            TABLES.filter_map { |part, table| [table, row(found.fetch(part), now)] if found[part] }.to_h
          end

          def held? = TABLES.keys.any? { |part| data[part] }

          # The file can be read and holds a part.
          def usable? = problem.nil? && held?

          private

          def data
            parsed = JSON.parse(@text)
            raise Invalid, "#{@path} is not a JSON object" unless parsed.is_a?(Hash)
            return parsed unless TABLES.keys.any? { |part| parsed[part] }

            named = parsed["intent"]
            raise Invalid, "#{@path} names intent #{named}, not intent #{@intent_id}" unless named == @intent_id

            parsed
          rescue JSON::ParserError
            raise Invalid, "#{@path} is not JSON"
          end

          def row(part, now) = { intent_id: @intent_id, data: JSON.pretty_generate(part), updated_at: now }
        end
      end
    end
  end
end
