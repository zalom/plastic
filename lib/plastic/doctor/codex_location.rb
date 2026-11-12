# frozen_string_literal: true

require_relative "check"

module Plastic
  module Doctor
    class CodexLocation
      def initialize(scope) = @scope = scope

      def check
        home = scope.home
        folder = File.join(home, ".codex")
        configured = scope.setting("CODEX_HOME").to_s
        problem = "#{configured} differs from the installer's #{folder}" unless configured.empty? || File.expand_path(configured, home) == folder
        Check.new("CODEX_HOME:", folder, "unset CODEX_HOME or set CODEX_HOME to #{folder}, then run plastic install --reinstall").judged(problem)
      end

      private

      attr_reader :scope
    end
  end
end
