# frozen_string_literal: true

module Plastic
  module Graph
    # A ref that names an intent, written `{intent_id}-{origin_id}`. Any
    # other ref, such as a ticket key or a link, is text and names none.
    IntentRef = Data.define(:intent_id, :origin_id)

    # What a ref names and whether it stands.
    class IntentRef
      def self.parse(ref)
        found = ref.to_s.match(/\A(?<intent_id>\d+[a-z0-9]*)-(?<origin_id>\h{4,})\z/)
        found && new(*found.captures)
      end

      # Why the ref cannot stand: it names an intent of this installation
      # that the store lacks. Nil when it stands.
      def problem(retrieval)
        return if origin_id != retrieval.origin_id || retrieval.intent(intent_id)

        "no intent #{intent_id} of this installation for the ref"
      end

      # What the ref names, in words.
      def line(own_origin_id)
        whose = { own_origin_id => "of this installation" }.fetch(origin_id, "of installation #{origin_id}, not in this store")
        "ref: intent #{intent_id} #{whose}"
      end
    end
  end
end
