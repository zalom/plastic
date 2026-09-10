# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "json"

require_relative "../scripts/lib/release_guard"

# PackageMetadataTest (intent 347, S3): package.json's repository.url becomes
# the canonical git+https form npm's provenance documentation shows, removing
# a variable from a path that cannot be tested before the owner configures
# the registry. Reads the real repository deliberately (ACTION_1 S3); this is
# one of the few files this intent allows to do so.
class PackageMetadataTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def package_json
    @package_json ||= JSON.parse(File.read(File.join(REPO, "package.json")))
  end

  def test_repository_url_is_the_canonical_git_https_form
    assert_equal "git+https://github.com/zalom/plastic.git", package_json["repository"]["url"]
  end

  # Note honestly what this cannot catch: a consistent three-file version bump
  # would still pass this test. The plan reviewer, not this test, is what
  # keeps this intent from becoming an accidental release.
  def test_version_files_agree
    result = ReleaseGuard.check(
      package_json: File.join(REPO, "package.json"),
      plugin_json: File.join(REPO, ".claude-plugin", "plugin.json"),
      marketplace_json: File.join(REPO, ".claude-plugin", "marketplace.json"),
      stable: false
    )
    assert result.ok?, "expected the three version files to agree: #{result.mismatches.inspect}"
  end
end

# ReleaseDocsTest (intent 347, S5): the release path changes, and both the
# changelog and the maintainer-facing internals doc must say so, in the
# section a reader who wants to know how @zalom/plastic reaches the registry
# would actually open.
class ReleaseDocsTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  CHANGELOG = File.join(REPO, "CHANGELOG.md")
  INTERNALS = File.join(REPO, "docs", "internals.md")

  # The pin follows the entry across the release that ships it: while 347 is
  # unreleased it lives under ## Unreleased, and the cut that ships it moves
  # it into the newest ## Released entry. Either way it sits at the top of
  # the changelog, where a reader asking how @zalom/plastic reaches the
  # registry looks first.
  def test_changelog_head_names_trusted_publishing
    body = File.read(CHANGELOG)
    unreleased_start = body.index("## Unreleased")
    released_start = body.index("## Released")
    refute_nil unreleased_start, "expected an ## Unreleased heading"
    refute_nil released_start, "expected a ## Released heading"
    entries = body[released_start..].split("\n- ")
    newest_release_entry = entries.length > 1 ? entries[1] : ""
    head = body[unreleased_start...released_start] + newest_release_entry
    assert_match(/trusted publish/i, head,
      "expected the Unreleased section or the newest release entry to mention trusted publishing")
    assert_includes head, "347"
  end

  def test_internals_doc_describes_the_publish_workflow
    body = File.read(INTERNALS)
    assert_includes body, ".github/workflows/publish.yml"
  end
end
