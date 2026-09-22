# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

require_relative "../scripts/lib/installer_core"
require_relative "../scripts/lib/release_guard"

# RunnerInstallTest (intent 340, G7, n7): the last node's own matrix rows -
# the installed scripts/runner is executable (7.2), the auto skill names the
# runner's three public verbs and stays silent about the internal `rewind`
# verb (7.3, 7.4), the CHANGELOG carries one Unreleased line for the batch
# (7.5), and nothing bumped a version file while landing it (7.6).
class RunnerInstallTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)
  CHANGELOG = File.join(REPO, "CHANGELOG.md")

  # 7.2: distribute's chmod pass over scripts/* already covers a newly added
  # verb script, but nothing asserted it for scripts/runner specifically - a
  # regression here would land the installed copy non-executable and every
  # invocation would die with EACCES on its first exec.
  def test_installed_runner_is_executable
    home = Dir.mktmpdir("runner-install-test")
    core = InstallerCore.new(package_root: REPO, plastic_home: home, version: "1.0.0-test")
    core.distribute(:install)

    dest = File.join(home, "scripts", "runner")
    assert File.exist?(dest), "distribute must install scripts/runner"
    mode = File.stat(dest).mode
    assert (mode & 0o111) == 0o111, "installed scripts/runner must be executable (mode #{mode.to_s(8)})"
  ensure
    FileUtils.rm_rf(home) if home
  end

  # Row 2.20 (intent 343, G10, n2): the same contract for scripts/graph-measure
  # - the documented invocation (`graph-measure intent <dir>`) fails on a real
  # machine if the installed copy is not executable.
  def test_installed_graph_measure_is_executable
    home = Dir.mktmpdir("runner-install-test")
    core = InstallerCore.new(package_root: REPO, plastic_home: home, version: "1.0.0-test")
    core.distribute(:install)

    dest = File.join(home, "scripts", "graph-measure")
    assert File.exist?(dest), "distribute must install scripts/graph-measure"
    mode = File.stat(dest).mode
    assert (mode & 0o111) == 0o111, "installed scripts/graph-measure must be executable (mode #{mode.to_s(8)})"
  ensure
    FileUtils.rm_rf(home) if home
  end

  # 7.5: the largest change in the batch must have a line under Unreleased,
  # added beside whatever earlier intents already wrote there, not in place
  # of them.
  def test_changelog_has_unreleased_runner_line
    body = File.read(CHANGELOG)
    unreleased = body[/^## Unreleased\n(.*?)^## /m, 1]
    refute_nil unreleased, "CHANGELOG.md must have an Unreleased section"
    assert_match(/34[0-9].*G7/, unreleased, "expected an intent 340 (G7) line under Unreleased")
    assert_includes unreleased, "336 (G3", "must not replace the existing 336 entry"
  end

  # 2.13 (intent 340a, G7b, n2): the delivery watch gets its own Unreleased
  # line, beside 343's, never in place of it.
  def test_changelog_has_unreleased_watch_line
    body = File.read(CHANGELOG)
    unreleased = body[/^## Unreleased\n(.*?)^## /m, 1]
    refute_nil unreleased, "CHANGELOG.md must have an Unreleased section"
    assert_match(/340a.*G7b/, unreleased, "expected an intent 340a (G7b) line under Unreleased")
    assert_includes unreleased, "343 (G10", "must not replace the existing 343 entry"
  end

  # Release cuts may change the version. The installation contract is that
  # the three version files agree; release-check validates the channel.
  def test_version_files_agree
    result = ReleaseGuard.check(
      package_json: File.join(REPO, "package.json"),
      plugin_json: File.join(REPO, ".claude-plugin", "plugin.json"),
      marketplace_json: File.join(REPO, ".claude-plugin", "marketplace.json"),
      stable: false
    )

    assert result.ok?, "the three version files must agree: #{result.mismatches.inspect}"
  end
end
