# frozen_string_literal: true

require_relative "check"

module Plastic
  module Doctor
    class VersionRecord
      def initialize(path, running)
        @path = path
        @running = running
      end

      def check(label, install:)
        return Check.finding(label, "no installation record at #{path}", install) unless recorded
        return Check.ok(label, "#{running} matches #{path}") if recorded == running

        Check.finding(label, "#{running} runs, but #{path} records #{recorded}", "#{install} --reinstall")
      end

      private

      attr_reader :path, :running

      def recorded = (@recorded ||= File.file?(path) ? File.read(path).strip : nil)
    end
  end
end
