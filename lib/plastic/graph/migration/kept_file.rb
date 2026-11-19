# frozen_string_literal: true

require "digest"
require_relative "../knowledge/sync_selection"

module Plastic
  module Graph
    # One row of sqlar: the path it names in the store folder, its bytes, its intent and the origin that wrote it.
    KeptFile = Data.define(:name, :data, :intent_id, :origin_id) do
      def self.from(row) = new(**row.slice("name", "data", "intent_id", "origin_id").transform_keys(&:to_sym))

      def bytes = data.to_s

      def digest = Digest::SHA256.hexdigest(bytes)

      def path(root) = File.expand_path(name, root)

      def inside?(root) = path(root).start_with?(File.join(root, ""))

      # The path inside its intent folder, or nil for a store-level path such as originals/.
      def in_intent = name[Knowledge::SyncSelection::INTENT_FILE, 1]

      # The intent folder the path lies in, such as store/1--alpha, or nil for a store-level path.
      def intent_folder = in_intent && name.split("/").first(2).join("/")
    end
  end
end
