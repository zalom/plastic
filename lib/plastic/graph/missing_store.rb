# frozen_string_literal: true

require "shellwords"

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

      def next_command(path = nil) = if global?
                                       "plastic install --reinstall"
                                     else
                                       "plastic project new #{store} #{path ? Shellwords.escape(path) : "PATH"}"
                                     end

      private

      def global? = store == GLOBAL
    end
  end
end
