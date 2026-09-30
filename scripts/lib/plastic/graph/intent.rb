# frozen_string_literal: true

require_relative "record"
require_relative "../invalid"

module Plastic
  module Graph
    # An intent: one piece of work. `id` is the row's local number;
    # `intent_id` is the Luhmann id people use, and with `origin_id` it names
    # the intent across installations. `ref` points at a ticket, a link or
    # another intent as `{intent_id}-{origin_id}`, and is never a copy.
    #
    # A Luhmann id alternates number and letter: 307 gives 307a, 307a gives
    # 307a1. `parent_id` is the id the last run was appended to.
    Intent = Data.define(:id, :intent_id, :parent_id, :ref, :origin_id, :slug, :title, :kind, :status, :disposition,
      :opened_at, :closed_at, :updated_at) do
      include Record

      def self.segments(id) = id.to_s.scan(/\d+|[a-z]+/).map { |part| part.match?(/\d/) ? [0, part.to_i] : [1, part] }

      def self.next_child(parent, taken)
        suffixes = parent.to_s.match?(/[a-z]\z/) ? (1..99).map(&:to_s) : ("a".."z").to_a
        candidates = suffixes.map { |suffix| "#{parent}#{suffix}" }
        candidates.find { |candidate| !taken.include?(candidate) } or raise Invalid, "#{parent} has no free child id"
      end

      def self.next_root(taken) = (taken.grep(/\A\d+\z/).map(&:to_i).max.to_i + 1).to_s

      def self.parent_of(id)
        runs = id.to_s.scan(/\d+|[a-z]+/)
        runs[0..-2].join if runs.size > 1
      end

      def self.slug_for(title) = title.downcase.scan(/[a-z0-9]+/).first(6).join("-")

      def segments = Intent.segments(intent_id)

      # The intent's folder, relative to the store folder.
      def dir = "store/#{intent_id}--#{slug}"

      def file = "#{intent_id}--#{slug}.md"

      # The fields store/index.json lists, in order.
      def index_h = Intent::INDEX_FIELDS.to_h { |field| [field.to_s, public_send(field)] }
    end
    Intent::STATUSES = %w[open active parked future done abandoned].freeze
    Intent::NEW_STATUSES = %w[open active parked future].freeze
    Intent::INDEX_FIELDS = %i[intent_id origin_id parent_id ref slug title kind status disposition opened_at closed_at].freeze
  end
end
