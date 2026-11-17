# frozen_string_literal: true

require_relative "../config"
require_relative "../config/layout"

module Plastic
  module Installations
    # What the person set with plastic config set that an install reads: the model and
    # effort of each agent role for one harness, whether the advisor is on, and
    # whether the status line is on.
    class Choices
      SECTIONS = { "claude" => "claude-code" }.freeze

      def initialize(home)
        @home = home
      end

      def models(harness: "claude") = overrides(harness, "models")

      def efforts(harness: "claude") = overrides(harness, "efforts")

      def advisor? = Config.new(@home).flag(%w[advisor enabled], default: true)

      def statusline? = Config.new(@home).flag(["statusline"], default: false)

      private

      def overrides(harness, part)
        config = Config.new(@home, harness: SECTIONS.fetch(harness, harness))
        Config::Layout.within(config.overrides, "agents", part).reject { |_agent, value| value.is_a?(Hash) }
      end
    end
  end
end
