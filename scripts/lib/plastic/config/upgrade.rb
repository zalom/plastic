# frozen_string_literal: true

require_relative "document"
require_relative "agent_renames"

module Plastic
  class Config
    # Brings the config file up to date at install: a flat file moves into the
    # layout, and the settings of a retired agent move to the agent that
    # replaced it. Returns the agents it moved.
    class Upgrade
      def initialize(path)
        @document = Document.new(path)
      end

      def call
        @document.migrate
        renamed = AgentRenames.new(@document.root).apply
        @document.save unless renamed.empty?
        renamed
      end
    end
  end
end
