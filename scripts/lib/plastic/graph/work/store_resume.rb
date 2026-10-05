# frozen_string_literal: true

require_relative "next_pick"
require_relative "next_offer"
require_relative "last_savepoints"
require_relative "../knowledge/store_folder"

module Plastic
  module Graph
    module Work
      # Where one store's work stopped, read from its rows alone: the intent
      # in play, its done and in-progress nodes, its last savepoints and the
      # command that runs next. A store whose rows hold no intent while its
      # folder holds intent folders says so and names what rebuilds the rows.
      class StoreResume
        SAVEPOINTS = 5
        IN_PROGRESS = %w[claimed parked failed].freeze
        GAP = "no command rebuilds these rows today"
        REBUILD = "plastic sync up --project %s --overwrite rebuilds them from the files; the owner settles that step"

        def initialize(retrieval, folder, session)
          @retrieval = retrieval
          @folder = folder
          @session = session
        end

        def slug = @retrieval.store

        # The label and value of each line to print, the store first.
        def rows = [["store:", slug], *body_rows, ["then:", then_text]]

        # The command to run next and why, or nil when the store has none.
        def next_step
          return if rebuild?

          command, why, = offer
          return if command == "none"

          [command || "plastic next", why]
        end

        private

        def pick = @pick ||= NextPick.new(@retrieval, @session)

        def offer = @offer ||= NextOffer.new(@retrieval, pick).call

        def rebuild? = @retrieval.intents.empty? && @folder.intent_dirs.any?

        def indexed? = @folder.exist?(Knowledge::StoreFolder::INDEX)

        def then_text
          return (indexed? ? format(REBUILD, slug) : GAP) if rebuild?

          command, why, handoff = offer
          handoff || "#{command} (because #{why})"
        end

        def body_rows
          return [["rows:", "none; the files hold #{@folder.intent_dirs.size} intent folders"]] if rebuild?

          [*in_play_rows, *node_rows, *savepoint_rows]
        end

        def in_play_rows
          return [["in play:", "none alone"], *pick.candidates.map { |intent| ["open:", intent.heading] }] if pick.ambiguous?

          [["in play:", pick.none? ? "none" : pick.intent.heading]]
        end

        def nodes = pick.intent ? @retrieval.nodes(pick.intent.intent_id) : []

        def node_rows = [*done_rows, *progress_rows]

        def done_rows = nodes.select { |node| node.state == "done" }.map { |node| ["done:", "#{node.id} #{node.title}"] }

        def progress_rows
          nodes.select { |node| IN_PROGRESS.include?(node.state) }.map { |node| ["in progress:", "#{node.id} #{node.state} #{node.title}"] }
        end

        def savepoint_rows
          return [] unless pick.intent

          LastSavepoints.new(@retrieval, SAVEPOINTS).lines(pick.intent.intent_id).map { |line| ["savepoint:", line] }
        end
      end
    end
  end
end
