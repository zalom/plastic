# frozen_string_literal: true

module Plastic
  module Graph
    # A store folder that does not exist. Only `Graph.create` makes one.
    class MissingStore < StandardError
      GLOBAL = "global"

      attr_reader :store

      def initialize(store)
        @store = store
        super(global? ? "the global store does not exist" : "the store of project #{store} does not exist")
      end

      def next_command = global? ? "plastic install" : "plastic project new #{store} PATH"

      private

      def global? = store == GLOBAL
    end
  end
end
