# frozen_string_literal: true

require_relative "../../config"
require_relative "legacy_path"

module Plastic
  module Graph
    module Knowledge
      # Which files of an intent folder a sync reads into rows. The notes are
      # always read: every Markdown file outside references/, the graph, the
      # context and the legacy action files. Images and videos, other
      # documents and the references/ folder are read only when their setting
      # under `sync` is on. `rel` is the path inside the intent folder.
      class SyncSelection
        OPTIONAL = %w[media documents references].freeze
        NOTES = %w[graph.json context.json].freeze
        REFERENCES = "references/"
        INTENT_FILE = %r{\Astore/[^/]*--[^/]*/(.+)\z}
        MEDIA = %w[.png .jpg .jpeg .gif .webp .svg .avif .heic .bmp .ico .tif .tiff
          .mp4 .mov .webm .m4v .avi .mkv].freeze

        def self.of(home)
          config = Config.new(home)
          new(OPTIONAL.select { |kind| config.flag(["sync", kind], default: false) })
        end

        def self.none = new([])

        def self.all = new(OPTIONAL)

        def self.kind_of(rel)
          return "references" if rel.start_with?(REFERENCES)
          return "notes" if note?(rel)

          MEDIA.include?(File.extname(rel).downcase) ? "media" : "documents"
        end

        def self.note?(rel) = File.extname(rel).casecmp?(".md") || NOTES.include?(rel) || LegacyPath.legacy?(rel)
        private_class_method :note?

        def initialize(kinds)
          @kinds = kinds
        end

        def read?(rel)
          kind = SyncSelection.kind_of(rel)
          kind == "notes" || @kinds.include?(kind)
        end

        # A path of the store folder: a file of an intent folder by its kind,
        # every other file of the store always.
        def selects?(path)
          rel = path[INTENT_FILE, 1]
          rel.nil? || read?(rel)
        end
      end
    end
  end
end
