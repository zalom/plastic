# frozen_string_literal: true

require_relative "../sync_types"

module Plastic
  class Config
    class Import
      class SyncTypesRule
        ON = [true, "true"].freeze
        ADDED = { "media" => SyncTypes::MEDIA, "documents" => SyncTypes::DOCUMENTS }.freeze

        def initialize(settings)
          @settings = settings
          @sync = settings["sync"]
        end

        def call = old_keys? ? @settings.merge("sync" => rewritten) : @settings

        private

        def old_keys? = @sync.is_a?(Hash) && ADDED.keys.any? { |key| @sync.key?(key) }

        def rewritten = @sync.except(*ADDED.keys).merge(types)

        def types = added.empty? ? {} : { "types" => SyncTypes.with(base, added) }

        def added = ADDED.select { |key, _types| ON.include?(@sync[key]) }.values.flatten

        def base = @sync.key?("types") ? SyncTypes.parse(@sync["types"]) : SyncTypes::DEFAULT
      end
    end
  end
end
