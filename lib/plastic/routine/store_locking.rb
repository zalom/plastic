# frozen_string_literal: true

require "shellwords"
require_relative "../store_lock"
require_relative "../cli/wiring"

module Plastic
  class Routine < CLI::Command
    # A routine that prints files, or says `holds_store_lock` in its class body,
    # holds the store lock from its hand-edit check through its print, when
    # sync.lock is on. A dry run takes none.
    module StoreLocking
      # The class-body word.
      module Declaration
        def holds_store_lock = (@holds_store_lock = true)

        def holds_store_lock? = @holds_store_lock == true || prints.any?
      end

      private

      def under_store_lock(&)
        lock = store_lock
        lock ? lock.hold(&) : yield
      rescue StoreLock::Busy => error
        raise Failed.new(error.message, next_command: Shellwords.join(["plastic", *words.to_s.split, *argv]), because: "another call holds the store lock")
      end

      def store_lock = (Wiring.store_lock(scope.plastic_home, scope.slug) if self.class.holds_store_lock? && !parsed[:dry_run])
    end
  end
end
