# frozen_string_literal: true

require_relative "agent_install"
require_relative "role_files"

module Plastic
  module Installations
    # The install for Hermes: skills and agent role files.
    class HermesInstall < AgentInstall
      private

      def copy
        skills(exclude: advisor_exclusions) + role_files
      end
    end
  end
end
