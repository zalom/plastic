# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module InstallerRelease
  # Unpacks a checked archive into a new directory under `parent` and returns the release package inside it.
  # A failure removes the directory it made.
  class Staging
    def self.create(archive:, version:, parent:)
      new(archive, Dir.mktmpdir("plastic-stage-", parent)).candidate(version)
    end

    def initialize(archive, stage)
      @archive = archive
      @stage = stage
    end

    def candidate(version)
      package = unpack
      Candidate.check(package, version)
      package
    rescue
      FileUtils.remove_entry(stage)
      raise
    end

    private

    attr_reader :archive, :stage

    def unpack
      unpacked = Archive.new(archive)
      unpacked.entry_names
      unpacked.extract_to(stage)
      File.join(stage, "package")
    end
  end

  # A release package is usable when it holds an executable launcher and a
  # VERSION file naming the expected version.
  class Candidate
    def self.check(path, version) = new(path, version).check

    def initialize(path, version)
      @path = path
      @version = version
    end

    def check
      problem = problems.find { |(_message, broken)| broken }
      raise VerificationError, problem.first if problem

      true
    end

    private

    attr_reader :path, :version

    def problems
      launcher = File.join(path, "bin", "plastic")
      recorded = File.file?(version_file) ? File.read(version_file).strip : nil
      [["candidate has no Plastic launcher", !(File.file?(launcher) && File.executable?(launcher))],
        ["candidate has no version", !recorded],
        ["candidate version does not match", recorded && recorded != version]]
    end

    def version_file = File.join(path, "VERSION")
  end
end
