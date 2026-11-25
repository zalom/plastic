# frozen_string_literal: true

require_relative "../config/agent_models"
require_relative "../config/layout"

module Plastic
  module Installations
    # What the person set with plastic config set that an install reads: the model and
    # effort of each agent role for one harness, whether the advisor is on, and
    # whether the status line is on.
    class Choices
      SECTIONS = { "claude" => "claude-code" }.freeze
      DEFAULT_WORKERS = 3

      def initialize(settings)
        @settings = settings
      end

      def models(harness: "claude") = overrides(harness, "models")

      def efforts(harness: "claude") = overrides(harness, "efforts")

      def max_workers = positive(@settings.config.value("driver.max_workers"))

      def advisor? = @settings.config.flag(%w[advisor enabled], default: true)

      def skipped_roles = advisor? ? [] : Config::AgentModels::CONSULTATION_AGENTS

      def statusline? = @settings.config.flag(["statusline"], default: false)

      private

      def positive(value)
        number = Integer(value.to_s, 10, exception: false)
        number&.positive? ? number : DEFAULT_WORKERS
      end

      def overrides(harness, part)
        config = @settings.config(harness: SECTIONS.fetch(harness, harness))
        Config::Layout.within(config.overrides, "agents", part).reject { |_agent, value| value.is_a?(Hash) }
      end
    end
  end
end
