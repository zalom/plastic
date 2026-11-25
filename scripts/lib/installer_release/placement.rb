# frozen_string_literal: true

module InstallerRelease
  # Moves a checked candidate into its release directory, and moves it back
  # when the activation that followed failed, so the same candidate can be
  # tried again.
  class Placement
    attr_reader :candidate

    def initialize(candidate, destination)
      @candidate = candidate
      @destination = destination
      @moved = false
    end

    def version = File.basename(destination)

    def check
      Candidate.check(candidate, version)
      raise ActivationError, "release version already exists" if File.exist?(destination)
    end

    def move
      File.rename(candidate, destination)
      @moved = true
    end

    def undo
      File.rename(destination, candidate) if @moved
    end

    private

    attr_reader :destination
  end
end
