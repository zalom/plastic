# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "installer_release"
require_relative "release_archive"

# Builds the three files a GitHub release carries and install.sh downloads:
# plastic.tgz, its checksum, and the manifest. The publish workflow, CI and
# the fresh install check all build through this class.
class ReleaseBuild
  ARCHIVE = "plastic.tgz"

  def self.call(version:, directory:, root:)
    FileUtils.mkdir_p(directory)
    ReleaseArchive.write(File.join(directory, ARCHIVE), version:, root:)
    seal(version, directory)
  end

  def self.seal(version, directory, pins: InstallerRelease::RubyPins.read)
    archive = File.join(directory, ARCHIVE)
    File.write("#{archive}.sha256", "#{Digest::SHA256.file(archive).hexdigest}  #{ARCHIVE}\n")
    release = InstallerRelease::Manifest.identity(version).merge("platform" => "universal", "architecture" => "universal")
    InstallerRelease::Manifest.write(File.join(directory, "plastic.manifest.json"), archive:, release:, ruby_builds: pins)
  end
end
