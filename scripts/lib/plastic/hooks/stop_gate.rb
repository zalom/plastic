# frozen_string_literal: true

module Plastic
  module Hooks
    # Whether `hook record` blocks the stop event. It blocks only when the
    # harness says the stop hook is already active, `runner.stop_hook` is
    # armed, this session holds a live delivery lock of this store in auto
    # mode, and that intent has a node ready to run (review A11: it never
    # fires the stop itself, only a repeated one). Any error permits.
    class StopGate
      def initialize(event:, stop_hook:, retrieval:, session_id:)
        @event = event
        @stop_hook = stop_hook
        @retrieval = retrieval
        @session_id = session_id
      end

      # The block hash, or nil to permit.
      def decision
        return nil unless block?

        { "decision" => "block", "reason" => "Plastic: intent #{lock.intent_id} still has ready work. Run plastic next " \
                                              "for it and dispatch what it prints before stopping." }
      rescue
        nil
      end

      private

      def block?
        @event[:stop_hook_active] == true && @stop_hook && !lock.nil? && @retrieval.ready_nodes(lock.intent_id).any?
      end

      def lock
        @lock ||= @retrieval.locks_of(@session_id).find { |held| held.store == @retrieval.store && held.mode == "auto" && held.live? }
      end
    end
  end
end
