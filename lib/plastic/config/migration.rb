# frozen_string_literal: true

module Plastic
  class Config
    # A flat config moved into the layout: the agent models, efforts and
    # advisor default of each model family go to its harness section, the
    # agent type is dropped, and every other setting goes to `global`.
    class Migration
      FAMILIES = { "claude" => "claude-code", "codex" => "codex" }.freeze
      MOVED = { "agent" => %w[type], "agents" => %w[models efforts], "advisor" => FAMILIES.keys }.freeze
      PARTS = %w[models efforts].freeze

      def self.kept(key, value)
        return [key, value] unless MOVED.key?(key) && value.is_a?(Hash)

        rest = value.except(*MOVED[key])
        [key, rest] unless rest.empty?
      end

      def self.flat_models(section) = section.reject { |_key, value| value.is_a?(Hash) }

      def initialize(data)
        @version = data.slice("version")
        @flat = data.except("version")
      end

      def sections
        moved = harnesses
        base = @version.merge("global" => global)
        moved.empty? ? base : base.merge("harnesses" => moved)
      end

      private

      def global = @flat.filter_map { |key, value| Migration.kept(key, value) }.to_h

      def harnesses = FAMILIES.to_h { |family, name| [name, agents(family).merge(advisor(family))] }.reject { |_name, section| section.empty? }

      def agents(family)
        parts = PARTS.to_h { |part| [part, agent_part(part, family)] }.reject { |_part, value| value.empty? }
        parts.empty? ? {} : { "agents" => parts }
      end

      def advisor(family)
        default = Layout.within(@flat, "advisor", family)["default"]
        default ? { "advisor" => { "default" => default } } : {}
      end

      def agent_part(part, family)
        section = Layout.within(@flat, "agents", part)
        nested = Layout.within(section, family)
        (family == "claude" && part == "models") ? Migration.flat_models(section).merge(nested) : nested
      end
    end
  end
end
