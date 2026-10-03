# frozen_string_literal: true

require_relative "evidence_integrity_audit"
require_relative "evidence_integrity_rebuilder"
require_relative "evidence_integrity_snapshot"

module Plastic
  module Graph
    # Diagnoses and rebuilds rows that can be derived from immutable evidence.
    class EvidenceIntegrity
      # Raised when a current document has no immutable revision.
      class EvidenceLost < StandardError; end

      def initialize(database, origin_id, before_rebuild: -> {})
        @database = database
        @before_rebuild = before_rebuild
        @snapshot = EvidenceIntegritySnapshot.new(database, origin_id)
        @audit = EvidenceIntegrityAudit.new
        @rebuilder = EvidenceIntegrityRebuilder.new(origin_id)
      end

      # Rebuilds derived rows inside one immediate transaction.
      def repair
        @database.immediate_transaction do |batch, connection|
          @before_rebuild.call
          snapshot = @snapshot.capture(connection)
          report = @audit.report(snapshot)
          raise EvidenceLost, report.fetch(:missing).join("; ") unless report.fetch(:missing).empty?

          @rebuilder.rebuild(batch, snapshot)
        end
        report
      end

      def report = @audit.report(@snapshot.capture)
    end
  end
end
