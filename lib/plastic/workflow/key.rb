# frozen_string_literal: true

require_relative "../invalid"

module Plastic
  class Workflow
    # A workflow key read apart: :code_close_intent is the lane "code" and
    # the class CloseIntent, which lives in workflows/close_intent.rb.
    Key = Data.define(:lane, :snake) do
      def self.parse(key) = new(*key.to_s.split("_", 2))

      def class_name = snake.split("_").map(&:capitalize).join

      # The workflow class in `namespace`. A class already loaded is used as
      # it is; any other is required from workflows/ first. The key's lane
      # must match the class.
      def workflow_in(namespace)
        require_relative "../workflows/#{snake}" unless namespace.const_defined?(class_name, false)
        workflow = namespace.const_get(class_name, false)
        actual = workflow.lane
        raise Invalid, "#{lane}_#{snake} names a #{lane} workflow, and #{workflow} is a #{actual} workflow" unless actual == lane

        workflow
      end
    end
  end
end
