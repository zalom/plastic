# frozen_string_literal: true

require "shellwords"
require_relative "../store_lock"
require_relative "../cli/wiring"

module Plastic
  class Routine < CLI::Command
    # A routine that prints files, or says `holds_store_lock` in its class body,
    # holds the store lock from its hand-edit check through its print. A dry
    # run takes none.
    module StoreLocking
      # The class-body word.
      module Declaration
        def holds_store_lock = (@holds_store_lock = true)

        def holds_store_lock? = @holds_store_lock == true || prints.any?
      end

      private

      def under_store_lock(&)
        return yield unless store_lock?

        Wiring.store_lock(scope.plastic_home, scope.slug).hold(&)
      rescue StoreLock::Busy => error
        raise Failed.new(error.message, next_command: same_call, because: "another call holds the store lock")
      end

      # The command line of this call, to run again once the lock is free.
      def same_call = Shellwords.join(["plastic", *words.to_s.split, *argv])

      def store_lock? = self.class.holds_store_lock? && !parsed[:dry_run]
    end
  end
end
