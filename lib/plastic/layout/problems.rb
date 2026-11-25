# frozen_string_literal: true

module Plastic
  module Layout
    # What is wrong with a layout file, all at once: a missing key, an unknown state or an unknown sync word.
    class Problems
      SYNCS = %w[document legacy_rows lines skip report].freeze
      REPAIRS = %w[rename amend remove move rebuild].freeze
      FILE_KEYS = %w[name purpose required writer].freeze
      LEGACY_KEYS = %w[name match sync repair why].freeze
      STORE_FOLDER_REPAIRS = %w[remove remove_empty].freeze
      AMENDMENTS = %w[rename move remove revision link rebuild].freeze
      TOP = %w[version folder states files resources legacy machine store_root store_folder amendments].freeze

      def initialize(data)
        @data = data
      end

      def to_a = [*top_level, *file_problems, *legacy_problems, *store_folder_problems, *amendment_problems].freeze

      private

      def top_level = TOP.reject { |key| @data.key?(key) }.map { |key| "the layout has no #{key}" }

      def states = @data.fetch("states", [])

      def file_problems = @data.fetch("files", {}).flat_map { |role, entry| file_keys(role, entry) + file_states(role, entry) }

      def file_keys(role, entry) = (FILE_KEYS - entry.keys).map { |key| "file #{role} has no #{key}" }

      def file_states(role, entry) = (Array(entry["required"]) - states).map { |state| "file #{role} requires the unknown state #{state}" }

      def legacy_problems = @data.fetch("legacy", []).flat_map { |entry| legacy_keys(entry) + legacy_words(entry) }

      def legacy_keys(entry) = (LEGACY_KEYS - entry.keys).map { |key| "legacy entry #{entry["name"]} has no #{key}" }

      def legacy_words(entry)
        [("legacy entry #{entry["name"]} has the unknown sync #{entry["sync"]}" unless SYNCS.include?(entry["sync"])),
          ("legacy entry #{entry["name"]} has the unknown repair #{entry["repair"]}" unless REPAIRS.include?(entry["repair"])),
          ("legacy entry #{entry["name"]} moves with no target" if %w[move rename].include?(entry["repair"]) && entry["to"].nil?)].compact
      end

      def store_folder_problems
        @data.fetch("store_folder", {}).fetch("legacy", []).reject { |entry| STORE_FOLDER_REPAIRS.include?(entry["repair"]) }
          .map { |entry| "store folder entry #{entry["name"]} has the unknown repair #{entry["repair"]}" }
      end

      def amendment_problems = (AMENDMENTS - @data.fetch("amendments", {}).keys).map { |kind| "the amendments have no reason for #{kind}" }
    end
  end
end
