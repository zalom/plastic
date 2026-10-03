# frozen_string_literal: true

require_relative "../record"

module Plastic
  module Graph
    module Knowledge
      # A typed edge between knowledge, named by the ref of each end: a ruling
      # today, a document or an intent later. This stage writes only
      # `supersedes`, from a newer ruling's ref to the one it replaces.
      Link = Data.define(:from_ref, :to_ref, :kind, :at, :origin_id) do
        include Record

        def from_intent_id = from_ref.split("/").first

        def self.supersedes(ruling, target) = { from_ref: ruling.ref, to_ref: target.ref, kind: "supersedes", at: ruling.at }
      end
      Link::KINDS = %w[cites supersedes answers source chain].freeze
    end
  end
end
