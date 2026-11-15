# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "package_fixture"
require "plastic/installations/package_version"

class PackageVersionTest < Plastic::TestCase
  include PackageFixture

  def version(root) = Plastic::Installations::PackageVersion.new(root).call

  def test_the_version_file_comes_first
    root = File.join(@home, "both")
    write(File.join(root, "VERSION"), "2.0.3\n")
    write(File.join(root, "package.json"), JSON.generate("version" => "9.9.9"))

    assert_equal "2.0.3", version(root)
  end

  def test_package_json_is_the_fallback
    root = File.join(@home, "json")
    write(File.join(root, "package.json"), JSON.generate("version" => "2.1.0-beta.1"))

    assert_equal "2.1.0-beta.1", version(root)
  end

  def test_a_package_with_neither_file_raises_naming_both
    root = File.join(@home, "none")
    error = assert_raises(RuntimeError) { version(root) }

    assert_includes error.message, "cannot determine the package version"
  end
end
