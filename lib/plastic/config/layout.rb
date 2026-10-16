# frozen_string_literal: true

require_relative "migration"

module Plastic
  class Config
    # The file's data in the layout Plastic reads: `version`, a `global`
    # section and a `harnesses` section keyed by harness name. A file written
    # before the layout existed is flat; it reads as the sections it moves to.
    class Layout
      SECTIONS = %w[version global harnesses].freeze

      def self.within(data, *keys) = keys.reduce(data) { |hash, key| hash_at(hash, key) }

      def self.hash_at(hash, key)
        value = hash[key]
        value.is_a?(Hash) ? value : {}
      end

      def initialize(data)
        @data = data.is_a?(Hash) ? data : {}
      end

      def sectioned? = (@data.keys - SECTIONS).empty?

      def sections = sectioned? ? @data : Migration.new(@data).sections
    end
  end
end
