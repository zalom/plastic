# frozen_string_literal: true

require_relative "../cli/wiring"
require_relative "../config/agent_models"
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

      def advisor? = Wiring.config(@home).flag(%w[advisor enabled], default: true)

      def skipped_roles = advisor? ? [] : Config::AgentModels::CONSULTATION_AGENTS

      def statusline? = Wiring.config(@home).flag(["statusline"], default: false)

      private

      def overrides(harness, part)
        config = Wiring.config(@home, harness: SECTIONS.fetch(harness, harness))
        Config::Layout.within(config.overrides, "agents", part).reject { |_agent, value| value.is_a?(Hash) }
      end
    end
  end
end
