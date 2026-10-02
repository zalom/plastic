# frozen_string_literal: true

require_relative "architecture_status"
require "json"

module Plastic
  module Commands
    # Generates a snapshot only through an explicit public command.
    class ArchitectureRefresh < ArchitectureStatus
      writes :knowledge

      def call
        previous = stored_receipt
        result = adapter.refresh(repository:, prior: previous)
        raise CLI::Command::Failure, "Enola could not generate an architecture snapshot" unless result.fetch(:success)

        current = current_receipt.merge("worktree_hash" => worktree_hash)
        persist(current)
        output.row("architecture", current)
        output.next_step("none", because: "the architecture snapshot was refreshed")
      end

      private

      def adapter = @adapter ||= Architecture::EnolaAdapter.new

      def receipt = adapter.snapshot(repository:, binary_sha256:, archive_sha256: nil, revision:, dirty:)

      def persist(receipt)
        graphs.databases.fetch(:knowledge).transaction do |batch|
          batch.put(:architecture_receipts, { provider: "enola", data: JSON.generate(receipt), updated_at: Plastic.now })
        end
      end
    end
  end
end
