# frozen_string_literal: true

require_relative "../cli/command"
require_relative "../architecture/enola_adapter"
require_relative "../graph"
require "json"
require "shellwords"
require_relative "../architecture/source_state"

module Plastic
  module Commands
    # Reads architecture facts without generating a snapshot.
    class ArchitectureStatus < CLI::Command
      reads :knowledge

      def call
        output.row("architecture", receipt)
        output.next_step(refresh_command, because: "an explicit refresh updates the architecture snapshot")
      end

      private

      def receipt
        Architecture::ReceiptFreshness.new(current: current_receipt, saved: stored_receipt, worktree_hash: source_state.worktree_hash).receipt
      end

      def repository = scope.project_path

      def refresh_command
        project = parsed[:project]
        project ? "plastic architecture refresh --project #{Shellwords.shellescape(project)}" : "plastic architecture refresh"
      end

      def current_receipt
        Architecture::EnolaAdapter.new.snapshot(source: source_state.source, identity: source_state.identity)
      end

      def stored_receipt
        row = graphs.databases.fetch(:knowledge).row("SELECT data FROM architecture_receipts WHERE provider = :provider AND origin_id = :origin",
          provider: "enola", origin: graphs.retrieval.origin_id)
        row ? JSON.parse(row.fetch("data")) : nil
      end

      def source_state = @source_state ||= Architecture::SourceState.new(repository)
    end
  end
end
