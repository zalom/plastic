# frozen_string_literal: true

require_relative "enola_provenance"
require_relative "enola_snapshot"

module Plastic
  module Architecture
    # Reads Enola facts without allowing retrieval to generate an index.
    class EnolaAdapter
      VERSION = EnolaProvenance::VERSION
      ARCHIVE_SHA256 = EnolaProvenance::ARCHIVE_SHA256
      BINARY_SHA256 = EnolaProvenance::BINARY_SHA256

      def initialize(command: EnolaCommand.new)
        @provenance = EnolaProvenance.new(command:)
        @snapshot = EnolaSnapshot.new(provenance: @provenance)
      end

      def receipt(identity:)
        @provenance.receipt(identity)
      end

      def snapshot(source:, identity:)
        @snapshot.receipt(source:, identity:)
      end

      def refresh(repository:, prior:)
        successful = @provenance.refresh(repository)
        { success: successful, receipt: successful ? nil : prior }
      end
    end
  end
end
