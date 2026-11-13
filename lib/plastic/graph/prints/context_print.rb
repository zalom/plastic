# frozen_string_literal: true

require "json"
require_relative "print"

module Plastic
  module Graph
    module Prints
      # The context.json print of an intent: its saved discovery and context.
      module ContextPrint
        module_function

        def call(intent, rows)
          id = intent.intent_id
          held = [rows.discoveries(id).first, rows.contexts(id).first]
          return [] if held.compact.empty?

          data = { "intent" => id, "discovery" => readable(held.first),
                   "context" => readable(held.last) }
          [Print.text("#{intent.dir}/context.json", :knowledge, "#{JSON.pretty_generate(data)}\n")]
        end

        def readable(row)
          JSON.parse(row.data) if row
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
