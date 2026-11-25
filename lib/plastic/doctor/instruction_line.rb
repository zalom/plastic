# frozen_string_literal: true

module Plastic
  module Doctor
    class InstructionLine
      def initialize(path, pattern)
        @path = path
        @pattern = pattern
      end

      def problem
        return "#{path} is missing" unless File.file?(path)

        "#{path} has no Plastic line" unless File.foreach(path).any? { |line| pattern.match?(line) }
      end

      private

      attr_reader :path, :pattern
    end
  end
end
