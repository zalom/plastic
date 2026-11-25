# frozen_string_literal: true

module Plastic
  module Harnesses
    # The names of the processes above this one, nearest first, read from
    # the /proc folder. A system with no /proc folder has no ancestors here:
    # Plastic starts no process to ask.
    class Processes
      DEPTH = 64

      def self.none = new(root: nil, pid: 0)

      def self.current = new(root: "/proc", pid: Process.pid)

      def self.parsed(text)
        close = text.rindex(")")
        [text[(text.index("(") + 1)...close], text[(close + 2)..].split[1].to_i]
      end

      def initialize(root:, pid:)
        @root = root
        @pid = pid
      end

      def ancestors = (@ancestors ||= above(@pid, DEPTH))

      private

      def above(pid, depth)
        parent = stat(pid)&.last
        entry = parent && depth.positive? && stat(parent)
        entry ? [entry.first, *above(parent, depth - 1)] : []
      end

      def stat(pid)
        path = @root && File.join(@root, pid.to_s, "stat")
        Processes.parsed(File.read(path)) if path && File.file?(path)
      rescue SystemCallError
        nil
      end
    end
  end
end
