# frozen_string_literal: true

require_relative "../../plastic"
require_relative "../invalid"

module Plastic
  class Workflow
    # A workflow key read apart with the class path it maps to: :code_close_intent
    # maps to Code::Intent::End, the lane "code" and the file
    # workflows/code/intent/end.rb. A path is walked one segment at a time, so
    # a segment never resolves through the ancestors of its parent.
    Key = Data.define(:text, :lane, :segments) do
      def self.parse(text, path) = new(text.to_s, text.to_s.split("_", 2).first, path.split("::"))

      def file = segments.map { |segment| Plastic.snake(segment) }.join("/")

      # The workflow class in `namespace`. A class already loaded is used as
      # it is; any other is required from workflows/ first. The key's lane
      # must match the class.
      def workflow_in(namespace)
        require_relative "../workflows/#{file}" unless loaded_in?(namespace)
        workflow = segments.inject(namespace) { |scope, segment| scope.const_get(segment, false) }
        actual = workflow.lane
        raise Invalid, "#{text} names a #{lane} workflow, and #{workflow} is a #{actual} workflow" unless actual == lane

        workflow
      end

      private

      def loaded_in?(namespace)
        segments.inject(namespace) do |scope, segment|
          return false unless scope.const_defined?(segment, false)

          scope.const_get(segment, false)
        end
        true
      end
    end
  end
end
