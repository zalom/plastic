# frozen_string_literal: true

require_relative "../inflector"
require_relative "../invalid"

module Plastic
  class Workflow
    # A workflow key read apart with the class path it maps to: :code_close_intent
    # maps to Code::Intent::End, the lane "code" and the file
    # workflows/code/intent/end.rb. A path is walked one segment at a time, so
    # a segment never resolves through the ancestors of its parent.
    Key = Data.define(:text, :lane, :segments) do
      def self.parse(text, path)
        name = text.to_s
        new(name, name.split("_", 2).first, path.split("::"))
      end

      def file = segments.map { |segment| Inflector.underscore(segment) }.join("/")

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

      def loaded_in?(namespace) = namespace.const_defined?(segments.join("::"), false)
    end
  end
end
