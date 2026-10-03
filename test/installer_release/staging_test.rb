# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseStagingTest < Minitest::Test
  include ReleaseHelper

  def test_stages_a_verified_candidate_in_its_own_directory
    archive = archive_with
    candidate = stage(archive, manifest_for(archive))

    assert candidate.start_with?(File.join(@root, "plastic-stage-"))
    assert_equal "2.0.3\n", File.read(File.join(candidate, "VERSION"))
  end

  def test_removes_the_stage_when_the_candidate_is_unusable
    archive = archive_with(version: "2.0.2")

    error = assert_raises(InstallerRelease::VerificationError) { stage(archive, manifest_for(archive)) }
    assert_equal "candidate version does not match", error.message
    assert_empty Dir.glob(File.join(@root, "plastic-stage-*"))
  end

  def test_checks_the_manifest_against_the_requested_release_not_its_own
    archive = archive_with
    manifest = manifest_for(archive)

    error = assert_raises(InstallerRelease::VerificationError) do
      InstallerRelease::Staging.create(archive: archive, manifest: manifest, parent: @root,
        expected_release: release.merge("version" => "2.0.4"))
    end
    assert_equal "release version does not match", error.message
  end

  def test_names_what_a_candidate_is_missing
    package = File.join(@root, "package")
    FileUtils.mkdir_p(package)

    assert_equal "candidate has no Plastic launcher", candidate_problem(package)
    write_package(package, "2.0.3", "new\n")
    File.delete(File.join(package, "VERSION"))

    assert_equal "candidate has no version", candidate_problem(package)
  end

  private

  def stage(archive, manifest) = InstallerRelease::Staging.create(archive: archive, manifest: manifest, parent: @root, expected_release: release)

  def candidate_problem(path)
    error = assert_raises(InstallerRelease::VerificationError) { InstallerRelease::Candidate.check(path, "2.0.3") }
    error.message
  end
end
