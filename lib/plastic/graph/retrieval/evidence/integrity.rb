# frozen_string_literal: true

require_relative "integrity_audit"
require_relative "integrity_rebuilder"
require_relative "integrity_snapshot"

module Plastic
  module Graph
    module Retrieval
      class Evidence
        # Diagnoses and rebuilds rows that can be derived from immutable evidence.
        class Integrity
          # Raised when a current document has no immutable revision.
          class EvidenceLost < StandardError
            def self.from(entries) = new(entries.join("; "))
          end
          # Holds the collaborators that read, assess, and rebuild derived rows.
          Components = Data.define(:snapshot, :audit, :rebuilder)

          def initialize(database, origin_id, before_rebuild: -> {})
            @database = database
            @before_rebuild = before_rebuild
            @components = Components.new(Evidence::IntegritySnapshot.new(database, origin_id), Evidence::IntegrityAudit,
              Evidence::IntegrityRebuilder.new(origin_id))
          end

          # Rebuilds derived rows inside one immediate transaction.
          def repair
            @database.immediate_transaction { |batch, connection| repair_snapshot(batch, connection) }
            report
          end

          def report = components.audit.report(components.snapshot.capture)

          private

          attr_reader :components

          def current_report(connection)
            snapshot = components.snapshot.capture_transaction(connection)
            [components.audit.report(snapshot), snapshot]
          end

          def repair_snapshot(batch, connection)
            @before_rebuild.call
            report, snapshot = current_report(connection)
            reject_missing(report)
            components.rebuilder.rebuild(batch, snapshot)
            report
          end

          def reject_missing(report)
            missing = report.fetch(:missing)
            raise EvidenceLost.from(missing) unless missing.empty?
          end
        end
      end
    end
  end
end
