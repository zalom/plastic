# frozen_string_literal: true

require_relative "../wiring"
require_relative "../../graph/missing_store"
require_relative "../../graph/behind"

module Plastic
  class CLI
    class Command
      # The store a call works on: its scope, made by the source the call
      # gives, and its graphs, each made on first use. A call that never
      # reached the store renews nothing.
      class Workspace
        attr_reader :environment

        def initialize(environment, source)
          @environment = environment
          @source = source
          @scope = nil
          @graphs = nil
        end

        def scope = (@scope ||= @source.call)

        def graphs = (@graphs ||= open_graphs)

        def settings = Wiring.settings(scope.plastic_home, clock: @environment.clock)

        # Renews the claims of this session after the call, in the store the call reached and
        # only when its work database exists: a renewal never makes one.
        def renew_claims
          session = @environment.session
          return unless session && @scope

          opened = graphs
          opened.work.renew_claims(session) if File.exist?(opened.databases.fetch(:store).path)
        rescue SQLite3::Exception, Graph::MissingStore, Graph::OutOfStep
          nil
        end

        private

        def open_graphs = Wiring.graphs(home: scope.plastic_home, store: scope.slug, session: @environment.session, clock: @environment.clock)
      end
    end
  end
end
