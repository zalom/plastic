# frozen_string_literal: true

require_relative "command"
require_relative "scope"

module Plastic
  class CLI
    # The name of a project: lowercase letters, digits and dashes, and never
    # the name of the global store.
    class ProjectName
      PATTERN = /\A[a-z0-9][a-z0-9-]*\z/

      def initialize(text)
        @text = text
      end

      # The name, or the usage error or refusal that says why it cannot be one.
      def checked
        raise Command::Usage, "the name must be lowercase letters, digits and dashes" unless PATTERN.match?(@text)
        raise Command::Refusal, "#{Scope::GLOBAL} is the name of the global store, not of a project" if @text == Scope::GLOBAL

        @text
      end
    end
  end
end
