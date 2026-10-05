# frozen_string_literal: true

module Plastic
  module Hooks
    # Whether `hook record` blocks the stop event. It blocks on the first
    # stop when `runner.stop_hook` is armed, this session holds a live
    # delivery lock of this store in auto mode, and that intent has a node
    # ready to run. Once the harness reports `stop_hook_active`, a stop this
    # hook already blocked, it permits, so the session can always end. Any
    # error permits.
    class StopGate
      def initialize(event:, stop_hook:, retrieval:, session_id:, now: Time.now)
        @armed = event[:stop_hook_active] != true && stop_hook
        @retrieval = retrieval
        @session_id = session_id
        @now = now
      end

      # The block hash, or nil to permit.
      def decision
        intent_id = @armed && lock&.intent_id
        return nil unless intent_id && @retrieval.ready_nodes(intent_id).any?

        { "decision" => "block", "reason" => "Plastic: intent #{intent_id} still has ready work. Run plastic next " \
                                              "for it and dispatch what it prints before stopping." }
      rescue
        nil
      end

      private

      def lock = @retrieval.locks_of(@session_id).find { |held| held.store == @retrieval.store && held.mode == "auto" && held.live?(@now) }
    end
  end
end
