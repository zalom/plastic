# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require_relative "../scripts/lib/worktree"

# Runtime hermeticity test (intent 169, Defect 1). Cross-linked with the
# static guard in test/hermeticity_guard_test.rb: that file scans test SOURCE
# for missing isolation seams; it cannot catch a live Worktree.provision call
# resolving against the real ~/.plastic, which is exactly how 166 got bitten
# (a sandboxed board planted a real git worktree + branch in the operator's
# actual ~/.plastic). This file exercises `provision` itself, with NO `home:`
# override, and asserts every git path it computes stays under a
# `Dir.mktmpdir` sandbox. It fails against the pre-fix provision (which fell
# to `home: Dir.home`) and passes once `home_from_store` derives the sandbox
# home from the injected store.
class WorktreeHermeticityTest < Minitest::Test
  # Records every `run(*args)`. Reports success generally, and specifically
  # reports "true" for the `rev-parse --is-inside-work-tree` git-repo probe so
  # the code worktree path is exercised too (mirrors test/worktree_test.rb's
  # FakeRunner pattern). No real git process ever runs.
  class RecordingRunner
    attr_reader :calls

    def initialize
      @calls = []
    end

    def run(*args)
      str_args = args.map(&:to_s)
      @calls << str_args
      if str_args.include?("rev-parse") && str_args.include?("--is-inside-work-tree")
        Worktree::ShellRunner::Result.new(0, "true\n", "")
      else
        Worktree::ShellRunner::Result.new(0, "", "")
      end
    end
  end

  def setup
    @sandbox = Dir.mktmpdir("hermeticity-sandbox")
    @plastic_home = File.join(@sandbox, ".plastic")
    FileUtils.mkdir_p(@plastic_home)
    @repo = File.join(@sandbox, "apps", "demo")
    FileUtils.mkdir_p(@repo)
    File.write(File.join(@plastic_home, "projects.yml"),
               { "projects" => { "demo" => { "path" => @repo } } }.to_yaml)
    @store = File.join(@plastic_home, "projects", "demo", "store")
    FileUtils.mkdir_p(@store)
    @real_worktrees_before = snapshot_real_worktrees
  end

  def teardown
    FileUtils.rm_rf(@sandbox)
  end

  # Read-only snapshot of the REAL ~/.plastic/.worktrees dir (never written to
  # by this test; the fake runner performs no real git calls). nil when the
  # dir does not exist on this machine.
  def snapshot_real_worktrees
    dir = File.join(Dir.home, ".plastic", ".worktrees")
    Dir.exist?(dir) ? Dir.children(dir).sort : nil
  end

  def bridge_data
    {
      "intent" => {
        "id" => "169",
        "dir" => "169--demo",
        "store" => @store,
        "name" => "demo",
      },
    }
  end

  def test_provision_with_no_home_override_stays_under_the_sandbox
    runner = RecordingRunner.new

    # NO `home:` kwarg passed: reproduces the exact 166 incident shape, where
    # `Bridge.arm` calls `Worktree.provision(data)` with no override
    # (scripts/lib/bridge.rb:794) and the pre-fix code fell to `Dir.home`.
    data = Worktree.provision(bridge_data, runner: runner)

    refute_empty runner.calls, "provision should have exercised git ops"

    dash_c_targets = runner.calls.select { |c| c[0] == "-C" }.map { |c| c[1] }
    add_targets = runner.calls.select { |c| c.include?("add") }.map do |c|
      idx = c.index("add")
      c[idx + 1]
    end
    refute_empty add_targets, "provision should have attempted at least one worktree add"

    # (1) every recorded -C target and worktree-add destination is under the sandbox.
    (dash_c_targets + add_targets).each do |path|
      assert path.start_with?(@sandbox),
        "expected #{path.inspect} to stay under sandbox #{@sandbox.inspect}"
    end

    # (2) regression for the 166 incident shape: no recorded path is under the
    # REAL ~/.plastic/.worktrees.
    real_worktrees_dir = File.join(Dir.home, ".plastic", ".worktrees")
    (dash_c_targets + add_targets).each do |path|
      refute path.start_with?(real_worktrees_dir),
        "regression: provision computed a path under the REAL #{real_worktrees_dir} " \
        "(the exact 166 incident shape)"
    end

    # (3) read-only before/after snapshot of the real .worktrees dir: no new entry.
    assert_equal @real_worktrees_before, snapshot_real_worktrees,
      "provision must not create any new entry in the real ~/.plastic/.worktrees"
  end
end
