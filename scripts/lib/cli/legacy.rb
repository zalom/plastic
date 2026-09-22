# frozen_string_literal: true

require "English"
require "open3"
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
      # A runner answers with the child's exit status. Asked to capture, it
      # answers with the child's stdout and that status, for a command that
      # renders the script's JSON as a screen. stderr is never captured, so a
      # warning the script writes there still reaches the terminal.
      DEFAULT_RUNNER = lambda do |path, arguments, capture: false|
        unless capture
          system(RbConfig.ruby, path, *arguments)
          next exit_code($CHILD_STATUS)
        end

        out, process = Open3.capture2(RbConfig.ruby, path, *arguments)
        [out, exit_code(process)]
      end

      NON_OWNER_EXIT_THREE = %w[verify-intent runner].freeze

      def self.exit_code(status)
        return Command::OK if status.success?

        status.exitstatus || Command::FAILED
      end

      def initialize(env:, runner: nil, output: nil, json: false)
        @output = output
        @json = json
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
        if @json
          text, status = @runner.call(script_path(script), arguments, capture: true)
          @output.raw(text) unless text.empty?
        else
          status = @runner.call(script_path(script), arguments)
        end
        raise Command::Refusal, "#{script} needs the owner" if owner_refusal?(script, status)

        status
      end

      def owner_refusal?(script, status)
        status == Command::REFUSED && !NON_OWNER_EXIT_THREE.include?(script)
      end

      def capture(script, *arguments)
        out, status = @runner.call(script_path(script), arguments, capture: true)
        raise Command::Refusal, "#{script} needs the owner" if owner_refusal?(script, status)

        [out, status]
      end
    end
  end
end
