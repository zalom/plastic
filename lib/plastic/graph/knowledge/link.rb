# frozen_string_literal: true

require_relative "../../clock"
require_relative "../record"

module Plastic
  module Graph
    module Knowledge
      # A typed edge between knowledge, named by the ref of each end: an intent, such as `4`, or a ruling, such as `4/D2`.
      # Its kind says how the ends relate, as `supersedes` from a newer intent to the one it replaces.
      Link = Data.define(:from_ref, :to_ref, :kind, :at, :origin_id) do
        include Record

        def joins?(edge) = [from_ref, to_ref, kind] == edge

        def needs? = kind == "needs"

        def ends = [from_ref, to_ref]

        def from_intent_id = from_ref.split("/").first

        def supersedes_from_another?(intent_id) = kind == "supersedes" && to_ref == intent_id && from_intent_id != intent_id

        def self.from_entry(entry, now)
          from_ref, to_ref, kind, at = entry.values_at("from_ref", "to_ref", "kind", "at")
          return unless [from_ref, to_ref].all? { |ref| ref.is_a?(String) && !ref.empty? } && Link::KINDS.include?(kind)

          { from_ref:, to_ref:, kind:, at: Plastic.utc(at) || now }
        end
      end
      Link::KINDS = %w[cites supersedes answers source chain needs].freeze
      Link::ALL_SQL = "SELECT * FROM links WHERE origin_id = :origin ORDER BY from_ref, to_ref, kind"
    end
  end
end
