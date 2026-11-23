# frozen_string_literal: true

require_relative "../../clock"
require_relative "../record"

module Plastic
  module Graph
    module Knowledge
      # A typed edge between knowledge, named by the ref of each end: a ruling
      # today, a document or an intent later. This stage writes only
      # `supersedes`, from a newer ruling's ref to the one it replaces.
      Link = Data.define(:from_ref, :to_ref, :kind, :at, :origin_id) do
        include Record

        def joins?(edge) = [from_ref, to_ref, kind] == edge

        def from_intent_id = from_ref.split("/").first

        def supersedes_from_another?(intent_id) = kind == "supersedes" && to_ref == intent_id && from_intent_id != intent_id

        def self.from_entry(entry, now)
          from_ref, to_ref, kind, at = entry.values_at("from_ref", "to_ref", "kind", "at")
          return unless [from_ref, to_ref].all? { |ref| ref.is_a?(String) && !ref.empty? } && Link::KINDS.include?(kind)

          { from_ref:, to_ref:, kind:, at: Plastic.utc(at) || now }
        end

        def self.supersedes(ruling, target) = { from_ref: ruling.ref, to_ref: target.ref, kind: "supersedes", at: ruling.at }
      end
      Link::KINDS = %w[cites supersedes answers source chain needs].freeze
      Link::ALL_SQL = "SELECT * FROM links WHERE origin_id = :origin ORDER BY from_ref, to_ref, kind"
    end
  end
end
