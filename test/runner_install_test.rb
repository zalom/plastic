# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "shellwords"

require_relative "../scripts/lib/installer_core"
require_relative "../scripts/lib/release_guard"

# RunnerInstallTest (intent 340, G7, n7): the last node's own matrix rows -
# the installed scripts/runner is executable (7.2), the auto skill names the
# runner's three public verbs and stays silent about the internal `rewind`
# verb (7.3, 7.4), the CHANGELOG carries one Unreleased line for the batch
# (7.5), and nothing bumped a version file while landing it (7.6).
class RunnerInstallTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)
  SKILL = File.join(REPO, "skills", "auto", "SKILL.md")
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

  # 7.3: the runner ships three public verbs (step, status, answer); the
  # skill body is the only place an operator learns the command exists.
  #
  # Row 7.12 (intent 343, G10, n7): graph-measure is the read-only sibling
  # over the same ledger, with its own three public verbs (intent, budget,
  # cohorts); the same skill body is the only place a lead learns it exists,
  # so this test carries both commands' verb-naming rows together.
  def test_skill_names_three_public_verbs
    body = File.read(SKILL)
    assert_includes body, "scripts/runner", "the skill body must name scripts/runner"
    assert_includes body, "`step`", "the skill body must name the step verb"
    assert_includes body, "`status`", "the skill body must name the status verb"
    assert_includes body, "`answer`", "the skill body must name the answer verb"

    assert_includes body, "scripts/graph-measure", "the skill body must name scripts/graph-measure"
    assert_includes body, "`intent`", "the skill body must name graph-measure's intent verb"
    assert_includes body, "`budget`", "the skill body must name graph-measure's budget verb"
    assert_includes body, "`cohorts`", "the skill body must name graph-measure's cohorts verb"
  end

  # 7.4: rewind (C15) is real and callable, but ships unpublished until a
  # later node measures a real run; the skill body must not tempt anyone
  # into a reset nobody has evidence for.
  def test_skill_does_not_name_rewind
    body = File.read(SKILL)
    refute_match(/rewind/i, body, "the skill body must not name the rewind verb")
  end

  # 7.12 (intent 340b, G7c, n7): until-empty is internal, like rewind - the
  # skill body must never grow a fourth verb 327 did not name.
  def test_skill_does_not_name_until_empty
    body = File.read(SKILL)
    refute_match(/until-empty|until empty/i, body, "the skill body must not name the until-empty verb")
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

  # 7.6: a version bump riding in on this feature branch would collide with
  # the release intent; the three repo version files must still agree, at
  # whatever version they carried before this node touched anything.
  def test_no_version_bump
    result = ReleaseGuard.check(
      package_json: File.join(REPO, "package.json"),
      plugin_json: File.join(REPO, ".claude-plugin", "plugin.json"),
      marketplace_json: File.join(REPO, ".claude-plugin", "marketplace.json"),
      stable: false
    )
    assert result.ok?, "the three version files must still agree: #{result.mismatches.inspect}"

    # The reference is the branch point with `alpha`, never a literal: this
    # branch merged `alpha` in at the close, and `alpha` carries release
    # bumps of its own, so a hard-coded version goes red on the next release
    # rather than on the thing this row guards against. Comparing against the
    # merge base still catches a bump that rode in on THIS branch, which is
    # the collision the row exists to prevent.
    base = `git -C #{Shellwords.escape(REPO)} merge-base HEAD alpha 2>/dev/null`.strip
    skip "no alpha branch in this checkout" if base.empty?

    base_package = `git -C #{Shellwords.escape(REPO)} show #{base}:package.json 2>/dev/null`
    refute_empty base_package, "could not read package.json at the branch point #{base}"
    assert_equal JSON.parse(base_package)["version"], result.version,
    "no version bump may ride in on this branch (branch point #{base[0, 7]})"
  end
end
