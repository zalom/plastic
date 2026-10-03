# frozen_string_literal: true

require "json"
require_relative "record"
require_relative "luhmann_id"

module Plastic
  module Graph
    # An intent: one piece of work. `id` is the row's local number;
    # `intent_id` is the Luhmann id people use, and with `origin_id` it names
    # the intent across installations. `ref` points at a ticket, a link or
    # another intent as `{intent_id}-{origin_id}`, and is never a copy.
    # `parent_id` is the Luhmann id the last run was appended to.
    Intent = Data.define(:id, :intent_id, :parent_id, :ref, :origin_id, :slug, :title, :kind, :status, :disposition,
      :opened_at, :closed_at, :updated_at)

    # What an intent derives from its fields: its folder, its rows and its own file.
    class Intent
      include Record

      OPEN = %w[open active].freeze
      ARCHIVABLE = %w[done abandoned future].freeze

      # Open or active: the work a resume lists.
      def open? = OPEN.include?(status)

      # Why the intent cannot archive, or nil when its status allows it.
      def archive_refusal
        return if ARCHIVABLE.include?(status)

        "intent #{intent_id} is #{status}; only done, abandoned and future intents archive"
      end

      # The id and the title, as people name the intent.
      def label = "#{intent_id} #{title}"

      # The label and the status.
      def heading = "#{label} (#{status})"

      def self.slug_for(title) = title.downcase.scan(/[a-z0-9]+/).first(6).join("-")

      def segments = LuhmannId.segments(intent_id)

      # The intent's folder, relative to the store folder.
      def dir = "store/#{intent_id}--#{slug}"

      def file = "#{intent_id}--#{slug}.md"

      # The row a new intent writes; the database gives `id` and stamps `origin_id`.
      def new_row = to_h.except(:id, :origin_id)

      def first_savepoint(session_id = nil) = { intent_id:, position: 1, at: opened_at, text: "Opened: #{title}", session_id: }

      # The row of the intent's own file in the knowledge graph.
      def document(origin_id) = { intent_id:, path: file, body: page(origin_id), updated_at: opened_at }

      # The intent's own file: front matter, then the sections a person fills.
      def page(origin_id)
        fields = { id: intent_id, intent: title, parent: parent_id, ref:, origin: origin_id, created: opened_at }.compact
        front = fields.map { |name, value| "#{name}: #{JSON.generate(value)}" }
        ["---", *front, "---", "", "# #{intent_id} - #{title}", "", "## Intent", "", title, "",
          "## Context", "", "## Outcome", "", "## Insights", ""].join("\n")
      end

      # The fields store/index.json lists, in order.
      def index_h = Intent::INDEX_FIELDS.to_h { |field| [field.to_s, public_send(field)] }
    end
    Intent::STATUSES = %w[open active parked future done abandoned].freeze
    Intent::NEW_STATUSES = %w[open active parked future].freeze
    Intent::INDEX_FIELDS = %i[intent_id origin_id parent_id ref slug title kind status disposition opened_at closed_at].freeze
  end
end
