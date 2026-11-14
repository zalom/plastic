# frozen_string_literal: true

require_relative "agent_install"
require_relative "role_files"

module Plastic
  module Installations
    # The install for Hermes: skills and agent role files.
    class HermesInstall < AgentInstall
      private

      def copy
        choices = @package.choices
        skills(exclude: advisor_exclusions) +
          RoleFiles.new(@package.root).call(File.join(@record.root, "agents"), models: choices.models, efforts: choices.efforts, advisor: choices.advisor?)
      end
    end
  end
end
