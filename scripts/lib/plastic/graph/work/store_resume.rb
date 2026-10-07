# frozen_string_literal: true

require_relative "rebuild"
require_relative "next_pick"
require_relative "next_offer"
require_relative "last_savepoints"
require_relative "node_lines"

module Plastic
  module Graph
    module Work
      # Where one store's work stopped, read from its rows alone: the intent
      # in play, its done and in-progress nodes, its last savepoints and the
      # command that runs next. A store whose rows hold no intent while its
      # folder holds intent folders says so and names sync up, which rebuilds the rows.
      class StoreResume
        SAVEPOINTS = 5

        # The rows hold the store's work.
        class InPlay
          def initialize(retrieval, session)
            @retrieval = retrieval
            @pick = NextPick.new(retrieval, session)
            @offer = NextOffer.new(retrieval, @pick).call
          end

          def rows = [["store:", @retrieval.store], *in_play_rows, *node_rows, *savepoint_rows, ["then:", then_text]]

          def next_step
            command, why, = @offer
            [command || "plastic next", why] unless command == "none"
          end

          private

          def then_text
            command, why, handoff = @offer
            handoff || "#{command} (because #{why})"
          end

          def in_play_rows
            return [["in play:", "none alone"], *@pick.candidates.map { |intent| ["open:", intent.heading] }] if @pick.ambiguous?

            [["in play:", @pick.none? ? "none" : @pick.intent.heading]]
          end

          def node_rows
            intent = @pick.intent
            intent ? NodeLines.new(@retrieval.nodes(intent.intent_id)).rows : []
          end

          def savepoint_rows
            intent = @pick.intent
            return [] unless intent

            LastSavepoints.new(@retrieval, SAVEPOINTS).lines(intent.intent_id).map { |line| ["savepoint:", line] }
          end
        end

        attr_reader :slug

        def initialize(retrieval, folder, session)
          @slug = retrieval.store
          rebuild = retrieval.intents.empty? && folder.intent_dirs.any?
          @view = rebuild ? Rebuild.new(@slug, folder) : InPlay.new(retrieval, session)
        end

        # The label and value of each line to print, the store first.
        def rows = @view.rows

        # The command to run next and why, or nil when the store has none.
        def next_step = @view.next_step
      end
    end
  end
end
