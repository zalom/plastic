# frozen_string_literal: true

module Plastic
  class Config
    # The file types a sync reads from the output folders of an intent, as bare
    # lowercase extensions. A setting holds them as a list or as a comma value.
    module SyncTypes
      DEFAULT = %w[md html].freeze
      MEDIA = %w[png jpg jpeg gif webp svg avif heic bmp ico tif tiff mp4 mov webm m4v avi mkv].freeze
      DOCUMENTS = %w[pdf doc docx odt rtf txt csv tsv xls xlsx ppt pptx json yml yaml xml].freeze

      def self.parse(value)
        items = value.is_a?(String) ? value.split(",") : Array(value)
        items.map { |item| item.to_s.strip.delete_prefix(".").downcase }.reject(&:empty?).uniq
      end

      def self.with(types, added) = (types | added)

      def self.with_media(types) = with(types, MEDIA)

      def self.without_media(types) = types - MEDIA
    end
  end
end
