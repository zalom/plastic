# frozen_string_literal: true

require_relative "architecture_status"
require "json"

module Plastic
  module Commands
    # Generates a snapshot only through an explicit public command.
    class ArchitectureRefresh < ArchitectureStatus
      writes :knowledge

      def call
        receipt = refreshed_receipt
        persist(receipt)
        output.row("architecture", receipt)
        output.next_step("none", because: "the architecture snapshot was refreshed")
      end

      private

      def adapter = @adapter ||= Architecture::EnolaAdapter.new

      def refreshed_receipt
        result = adapter.refresh(repository:, prior: stored_receipt)
        raise CLI::Command::Failure, "Enola could not generate an architecture snapshot" unless result.fetch(:success)

        current_receipt.merge("worktree_hash" => source_state.worktree_hash)
      end

      def persist(receipt)
        graphs.databases.fetch(:knowledge).transaction do |batch|
          batch.put(:architecture_receipts, { provider: "enola", data: JSON.generate(receipt), updated_at: Plastic.now })
        end
      end
    end
  end
end
