# frozen_string_literal: true

require "fileutils"
require_relative "archive"

module InstallerRelease
  # A checked Ruby archive unpacked in a staging folder, started once and
  # marked, then renamed into its folder and made read-only.
  class RubyStage
    def initialize(stage, pin, run)
      @stage = stage
      @pin = pin
      @run = run
    end

    def unpack(archive, folder)
      unpacked = File.join(stage, "unpacked")
      Archive.new(archive, limits: Rubies::LIMITS).extract_to(unpacked)
      File.rename(started(File.join(unpacked, pin.fetch("root"))), folder)
      FileUtils.chmod_R("a-w", folder)
    end

    private

    attr_reader :stage, :pin, :run

    def started(folder)
      printed = run.call(File.join(folder, "bin", "ruby"))
      raise VerificationError, "the Ruby #{pin.fetch("key")} does not start: #{printed.strip}" unless printed == pin.fetch("version")

      File.write(File.join(folder, Rubies::MARKER), "#{pin.fetch("sha256")}\n")
      folder
    end
  end
end
