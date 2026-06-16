require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/bridge"

# Tests for the Bash-edit gate (intent 27a). Mirrors code_gate_test.rb.
class BashGateTest < Minitest::Test
  # --- Task 1: bash_write_targets ---

  def targets(cmd)
    Bridge.bash_write_targets(cmd)
  end

  def test_redirect_truncate
    assert_equal ["out.txt"], targets("echo hi > out.txt")
  end

  def test_redirect_append
    assert_equal ["log.txt"], targets("echo hi >> log.txt")
  end

  def test_heredoc_redirect
    assert_equal ["f.rb"], targets("cat > f.rb <<EOF\nbody\nEOF")
  end

  def test_tee
    assert_equal ["a.txt"], targets("echo hi | tee a.txt")
  end

  def test_tee_append
    assert_equal ["a.txt"], targets("echo hi | tee -a a.txt")
  end

  def test_tee_multiple_files
    assert_equal ["a.txt", "b.txt"], targets("echo hi | tee a.txt b.txt")
  end

  def test_sed_inplace
    assert_equal ["file.rb"], targets("sed -i 's/a/b/' file.rb")
  end

  def test_sed_inplace_with_suffix
    assert_equal ["file.rb"], targets("sed -i.bak 's/a/b/' file.rb")
  end

  def test_cp
    assert_equal ["dest.rb"], targets("cp src.rb dest.rb")
  end

  def test_mv
    assert_equal ["dest.rb"], targets("mv src.rb dest.rb")
  end

  def test_cp_with_flags
    assert_equal ["dest"], targets("cp -r src dest")
  end

  def test_dd_of
    assert_equal ["disk.img"], targets("dd if=/dev/zero of=disk.img bs=1M")
  end

  def test_multiple_writes_in_one_command
    assert_equal ["x", "y"], targets("a > x; b >> y")
  end

  # --- false positives that MUST NOT be flagged ---

  def test_dev_null_redirect_excluded
    assert_equal [], targets("noisy > /dev/null")
  end

  def test_fd_dup_excluded
    assert_equal [], targets("cmd 2>&1")
  end

  def test_fd_to_dev_null_excluded
    assert_equal [], targets("cmd 2>/dev/null")
  end

  def test_plain_read_pipe_excluded
    assert_equal [], targets("cat path | grep x")
  end

  def test_grep_read_excluded
    assert_equal [], targets("grep x path")
  end

  def test_plain_read_excluded
    assert_equal [], targets("cat somefile")
  end

  # --- Task 2: bash_gate_decision ---

  def setup
    @home = Dir.mktmpdir("bash-gate-home")
    @store = File.join(@home, ".plastic", "projects", "demo", "store")
    @intent_dir = File.join(@store, "27--demo")
    FileUtils.mkdir_p(@intent_dir)
    File.write(File.join(@intent_dir, "27--demo.md"), "## Intent\nDemo\n")
    File.write(File.join(@intent_dir, "spec.md"), "spec\n")
    @cwd = File.join(@home, "code")
    FileUtils.mkdir_p(@cwd)
    @project_file = File.join(@cwd, "app.rb")
    File.write(@project_file, "puts 1\n")
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def bridge(auto:)
    {
      "intent" => { "id" => "27", "dir" => "27--demo", "store" => @store, "name" => "demo" },
      "build"  => { "auto" => auto },
    }
  end

  def decide(b, cmd)
    Bridge.bash_gate_decision(b, cmd, cwd: @cwd, home: @home)
  end

  def reach_how
    File.write(File.join(@intent_dir, "plan.md"), "plan\n")
    FileUtils.mkdir_p(File.join(@intent_dir, "actions"))
    File.write(File.join(@intent_dir, "checklist.md"), "- [ ] x\n")
  end

  def test_blocks_write_to_project_code_pre_how
    refute_nil decide(bridge(auto: true), "echo x > app.rb")
  end

  def test_blocks_write_to_project_code_absolute
    refute_nil decide(bridge(auto: true), "echo x > #{@project_file}")
  end

  def test_allows_when_auto_false
    assert_nil decide(bridge(auto: false), "echo x > app.rb")
  end

  def test_allows_when_no_bridge
    assert_nil decide(nil, "echo x > app.rb")
  end

  def test_allows_once_how_reached
    reach_how
    assert_nil decide(bridge(auto: true), "echo x > app.rb")
  end

  def test_allows_target_inside_intent_dir
    rel = File.join(@intent_dir, "spec.md")
    assert_nil decide(bridge(auto: true), "echo x > #{rel}")
  end

  def test_allows_target_under_plastic_home
    target = File.join(@home, ".plastic", "INDEX.md")
    assert_nil decide(bridge(auto: true), "echo x > #{target}")
  end

  def test_allows_read_only_command
    assert_nil decide(bridge(auto: true), "cat app.rb")
  end
end
