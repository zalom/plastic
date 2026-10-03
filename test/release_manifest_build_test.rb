# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class ReleaseManifestBuildTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SCRIPT = File.join(ROOT, "scripts", "build-release-manifest")

  def test_builds_a_manifest_for_the_named_archive_and_release
    Dir.mktmpdir do |directory|
      archive = File.join(directory, "plastic.tgz")
      File.binwrite(archive, "archive bytes")
      output = File.join(directory, "plastic.manifest.json")
      _stdout, stderr, status = Open3.capture3("ruby", SCRIPT, "--archive", archive, "--output", output,
        "--version", "2.0.3", "--channel", "latest", "--platform", "darwin",
        "--architecture", "arm64", chdir: ROOT)

      assert_predicate status, :success?, stderr
      manifest = JSON.parse(File.read(output))

      assert_equal "v2.0.3", manifest.dig("release", "tag")
      assert_equal "plastic.tgz", manifest.dig("archive", "name")
    end
  end
end
