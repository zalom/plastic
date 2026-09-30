# frozen_string_literal: true

module Plastic
  module Graph
    # A ref that names an intent, written `{intent_id}-{origin_id}`. Any
    # other ref, such as a ticket key or a link, is text and names none.
    IntentRef = Data.define(:intent_id, :origin_id) do
      def self.parse(ref)
        found = ref.to_s.match(/\A(?<intent_id>\d+[a-z0-9]*)-(?<origin_id>\h{4,})\z/)
        found && new(*found.captures)
      end
    end
  end
end
