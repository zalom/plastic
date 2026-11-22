# frozen_string_literal: true

module Plastic
  class Context
    # The graphs, the harness and the clock a call was given.
    Collaborators = Struct.new(:graphs, :harness, :clock) do
      def work = graphs[:work]

      def retrieval = graphs[:retrieval]

      def database(name) = graphs.fetch(:databases).fetch(name)

      def session = harness.session

      def harness_name = harness.name.to_s

      def user_home = harness.user_home

      def scope = harness.scope

      def settings = harness.settings
    end
  end
end
