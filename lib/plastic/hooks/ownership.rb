# frozen_string_literal: true

module Plastic
  module Hooks
    # Tells the hook commands this installation wrote, or an earlier install
    # wrote, from everyone else's, so an install replaces them and an
    # uninstall removes them.
    class Ownership
      # The launchers and the Codex dispatcher earlier installs wrote. A
      # command is theirs only when one of its words names one of these
      # files, never by a substring, so a user's plastic-writing-style stays.
      OLD_LAUNCHERS = %w[session-start check-update savepoint record close capture message-display stop statusline
        edit-gates bash-gate code-gate create-gate links-gate lock-gate savepoint-pre call-budget qmd-search
        retrieval-gate model-instructions opus-manual continue future-intent-check auto-arm gate-check
        power-tools].map { |name| "plastic-#{name}" }.push("codex-hook").freeze

      # True when a word of the command names an earlier install's launcher file.
      def self.old_launcher?(command) = command.split.map { |word| File.basename(word.delete(%("')), ".rb") }.intersect?(OLD_LAUNCHERS)

      def initialize(launchers)
        @launchers = launchers.compact
      end

      def own?(command)
        launchers.any? { |path| command == path || command.include?(%("#{path}")) } || self.class.old_launcher?(command)
      end

      private

      attr_reader :launchers
    end
  end
end
