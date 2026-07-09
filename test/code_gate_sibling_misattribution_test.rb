require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/bridge"

# Regression test for intent 168: scripts/hook-code-gate resolved its bridge through
# Bridge.discover_bridge, which applies the intent-90 strict per-session filter BEFORE
# any worktree check. In a parallel roadmap wave the orchestrator's guided intent keys
# its bridge by the real session id, while a derived-key auto sibling keys its own
# bridge by `auto-<hash>`. A subagent editing a file inside its OWN sibling's worktree
# inherits the orchestrator's session via CLAUDE_CODE_SESSION_ID, so the per-session
# filter discarded the sibling's own worktree-matching bridge and left only the guided
# bridge, which then failed worktree confinement for the WRONG intent. This test fails
# against the pre-fix resolver (exit 2 naming the guided intent 401) and passes once
# the edited file's worktree membership decides before the per-session filter (D1).
class CodeGateSiblingMisattributionTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-code-gate", __dir__)

  def setup
    @tmp = Dir.mktmpdir("code-gate-sibling-tmp")
    @home = Dir.mktmpdir("code-gate-sibling-home")
    @store = File.join(@home, ".plastic", "projects", "demo", "store")
    FileUtils.mkdir_p(@store)

    @session = "orchestrator-session" # the guided real session id hook-code-gate resolves

    # Guided intent G = 401, PRE-How (spec.md only, no plan.md/checklist.md).
    @dir_g = File.join(@store, "401--guided")
    FileUtils.mkdir_p(@dir_g)
    File.write(File.join(@dir_g, "401--guided.md"), "## Intent\nG\n")
    File.write(File.join(@dir_g, "spec.md"), "spec\n")

    # Derived intent D = 402, REACHED How (real plan.md + checklist.md, no sentinel).
    @dir_d = File.join(@store, "402--derived")
    FileUtils.mkdir_p(@dir_d)
    File.write(File.join(@dir_d, "402--derived.md"), "## Intent\nD\n")
    File.write(File.join(@dir_d, "spec.md"), "spec\n")
    File.write(File.join(@dir_d, "plan.md"), "plan\n")
    File.write(File.join(@dir_d, "checklist.md"), "- [x] done\n")

    @code_g = File.join(@home, "repo", ".claude", "worktrees", "401--guided")
    @code_d = File.join(@home, "repo", ".claude", "worktrees", "402--derived")
    FileUtils.mkdir_p(@code_g)
    FileUtils.mkdir_p(@code_d)
    @file_d = File.join(@code_d, "app.rb")
    File.write(@file_d, "puts 1\n")

    write_bridge("plastic-#{@session}--401.json",
                 session: @session, id: "401", dir: "401--guided",
                 auto: false, code: @code_g) # GUIDED

    @derived_key = Bridge.derive_key(@store, "402")
    write_bridge("plastic-#{@derived_key}--402.json",
                 session: @derived_key, id: "402", dir: "402--derived",
                 auto: true, code: @code_d)

    # Unrelated to either worktree/store, proving the fix does not rely on Dir.pwd.
    @unrelated_cwd = Dir.mktmpdir("code-gate-sibling-cwd")
  end

  def teardown
    FileUtils.rm_rf(@tmp)
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@unrelated_cwd)
  end

  def write_bridge(name, session:, id:, dir:, auto:, code:)
    data = {
      "session" => session,
      "intent" => { "id" => id, "dir" => dir, "store" => @store, "name" => "demo #{id}" },
      "build" => { "auto" => auto },
      "worktree" => { "code" => code, "provisioned" => true },
    }
    File.write(File.join(@tmp, name), JSON.generate(data))
  end

  def run_hook(file_path, session, content = nil)
    env = { "PLASTIC_TMP" => @tmp, "HOME" => @home, "CLAUDE_CODE_SESSION_ID" => nil }
    args = [RbConfig.ruby, SCRIPT, file_path, session]
    args << content if content
    Open3.capture3(env, *args, chdir: @unrelated_cwd)
  end

  # Regression (a): the guided session editing a file inside its DERIVED-KEY
  # sibling's own worktree must be allowed, and must never name the guided
  # intent. No plastic-ok marker is passed (no escape needed once fixed).
  def test_guided_session_editing_inside_derived_siblings_worktree_allows
    _out, err, status = run_hook(@file_d, @session)
    assert_equal 0, status.exitstatus
    refute_includes err, "intent 401"
  end

  # Regression (b): the fix must NOT start allowing shared-checkout writes. An
  # auto pre-How bridge editing a file OUTSIDE any worktree still blocks, naming
  # its own intent, because enclosing_worktree_dir(@shared) is nil and the edit
  # falls through to the unchanged pipeline (code_gate_decision).
  def test_shared_checkout_edit_outside_any_worktree_still_blocks
    dir_z = File.join(@store, "501--auto")
    FileUtils.mkdir_p(dir_z)
    File.write(File.join(dir_z, "501--auto.md"), "## Intent\nZ\n")
    File.write(File.join(dir_z, "spec.md"), "spec\n") # pre-How

    code_z = File.join(@home, "repo", ".claude", "worktrees", "501--auto")
    FileUtils.mkdir_p(code_z)

    write_bridge("plastic-#{@session}--501.json",
                 session: @session, id: "501", dir: "501--auto",
                 auto: true, code: code_z)

    shared = File.join(@home, "repo", "lib", "app.rb")
    FileUtils.mkdir_p(File.dirname(shared))
    File.write(shared, "puts 1\n")

    _out, err, status = run_hook(shared, @session)
    assert_equal 2, status.exitstatus
    assert_includes err, "intent 501"
  end
end
