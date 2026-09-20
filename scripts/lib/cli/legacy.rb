# encoding: UTF-8
# frozen_string_literal: true

require "English"
require "rbconfig"
require_relative "command"

# Plastic::CLI::Legacy (intent 363) - runs a script that has not moved into a
# module yet as a child process, and passes its output straight through. It is
# scaffolding: when the last family is migrated it is deleted, and the commands
# call their modules in the same process instead.
#
# A child that exits 3 refused, and the refusal travels as a Refusal so the
# agent is told to stop and ask rather than to retry with a flag. Every other
# status is handed back to the caller unchanged.
module Plastic
  class CLI
    class Legacy
      DEFAULT_RUNNER = lambda do |path, arguments|
        system(RbConfig.ruby, path, *arguments) ? 0 : ($CHILD_STATUS || $?)&.exitstatus || 1
      end

      def initialize(env:, runner: nil)
        @env = env
        @runner = runner || DEFAULT_RUNNER
      end

      def package_root
        @package_root ||= @env["PLASTIC_PACKAGE_ROOT"] || File.expand_path("../../..", __dir__)
      end

      def script_path(script)
        File.join(package_root, "scripts", script)
      end

      def run(script, *arguments)
        status = @runner.call(script_path(script), arguments)
        raise Command::Refusal, "#{script} needs the owner" if status == Command::REFUSED

        status
      end
    end
  end
end
