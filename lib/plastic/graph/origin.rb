# frozen_string_literal: true

require "fileutils"
require "securerandom"

module Plastic
  module Graph
    # The origin id of this installation: made on first use, kept under the
    # home, and stamped on every row a store database writes.
    class Origin
      FILE = "origin_id"

      def initialize(home)
        @home = home
      end

      def id = (@id ||= kept || made)

      private

      def path = File.join(@home, FILE)

      def kept
        text = File.exist?(path) && File.read(path).strip
        text unless text.to_s.empty?
      end

      def made
        FileUtils.mkdir_p(@home)
        fresh = SecureRandom.hex(4)
        File.write(path, "#{fresh}\n")
        fresh
      end
    end
  end
end
