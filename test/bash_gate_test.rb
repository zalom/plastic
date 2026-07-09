require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/db"

# Tests for the Bash-edit gate (intent 27a; interpreter writes, lock
# composition, and the plastic-ok escape from intent 108 D7).
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

  # --- Task 1: quote/heredoc-aware redirect parsing (intent 121) ---

  # False positive #1: the `>` inside a quoted `-> ` arrow is not a redirect.
  def test_quoted_arrow_is_not_a_redirect
    assert_equal [], targets(%q{git commit -m "Future -> Active"})
  end

  # A real redirect OUTSIDE the quote is still caught alongside the quoted arrow.
  def test_real_redirect_survives_quoted_arrow
    assert_equal ["out.txt"], targets(%q{git commit -m "a -> b" > out.txt})
  end

  # False positive #2: the closing `>` of a `<email>` trailer in a heredoc body
  # is not a redirect.
  def test_heredoc_body_email_trailer_is_not_a_redirect
    cmd = "git commit -F- <<EOF\n" \
          "message\n" \
          "Co-Authored-By: Name <noreply@example.com>\n" \
          "EOF"
    assert_equal [], targets(cmd)
  end

  # Fail OPEN: an unbalanced quote yields no target and does not raise.
  def test_unbalanced_quote_fails_open
    assert_equal [], targets(%q{echo "oops > file})
  end

  # Fail OPEN: an unterminated heredoc yields no target (even with a real `>`
  # on the opener line) and does not raise.
  def test_unterminated_heredoc_fails_open
    assert_equal [], targets("foo > out.txt <<EOF\nunterminated body")
  end

  # --- intent 121a: quoted-redirect-target regression ---

  # A double-quoted redirect target is unwrapped and captured, not blanked away.
  # RED on current main (pre-121a fix).
  def test_quoted_redirect_target_double
    assert_equal ["app.rb"], targets(%q{echo x > "app.rb"})
  end

  # Same, single-quoted.
  def test_quoted_redirect_target_single
    assert_equal ["app.rb"], targets(%q{echo x > 'app.rb'})
  end

  # Over-fix guard: the unquoted case must still work exactly as before.
  def test_unquoted_redirect_target_still_captured
    assert_equal ["app.rb"], targets("echo x > app.rb")
  end

  # Heredoc opener with a digit-leading delimiter (`<<1EOF`) is recognized, so
  # a `>` inside its body (an email trailer) still yields no phantom target.
  def test_digit_leading_heredoc_body_masked
    cmd = "git commit -F- <<1EOF\n" \
          "message\n" \
          "Co-Authored-By: Name <noreply@example.com>\n" \
          "1EOF"
    assert_equal [], targets(cmd)
  end

  # A real redirect on a `<<1EOF` opener line is still parsed.
  def test_digit_leading_heredoc_real_redirect
    cmd = "cat > out.txt <<1EOF\nbody\n1EOF"
    assert_equal ["out.txt"], targets(cmd)
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

  # --- interpreter writes (intent 108, D7) -----------------------------------

  def test_ruby_e_file_write_to_an_absolute_path_is_a_target
    cmd = %q{ruby -e 'File.write("/Users/x/proj/app.rb", "code")'}
    assert_includes targets(cmd), "/Users/x/proj/app.rb"
  end

  def test_python_c_open_write_is_a_target
    cmd = %q{python3 -c 'open("/Users/x/proj/app.py", "w").write("x")'}
    assert_includes targets(cmd), "/Users/x/proj/app.py"
  end

  def test_interpreter_without_write_verb_is_not_flagged
    cmd = %q{ruby -e 'puts File.read("/Users/x/proj/app.rb")'}
    assert_empty targets(cmd)
  end

  def test_sanctioned_arm_one_liner_is_not_flagged
    cmd = %q{ruby -r ~/.plastic/scripts/lib/bridge -e 'Bridge.arm_guided(ENV["CLAUDE_CODE_SESSION_ID"], intent_id: "96", intent_dir: "/s/96--demo", store: "/s", name: "demo")'}
    assert_empty targets(cmd)
  end

  def test_interpreter_write_without_a_quoted_path_is_not_flagged
    cmd = %q{ruby -e 'File.write(ARGV[0], "x")' some_file}
    assert_empty targets(cmd)
  end

  # --- lock-gate composition (intent 108, D7) --------------------------------

  def activate_intent_27
    File.write(File.join(File.dirname(@store), "INDEX.md"),
               "## Active\n- [27 — demo](27--demo/27--demo.md)\n\n## Future\n")
  end

  def acquire_lease(session)
    conn = Plastic::DB.connect(File.dirname(@store))
    Plastic::DB::Leases.acquire(conn, "27", session: session, host: "h")
  end

  def test_bash_gate_blocks_an_interpreter_write_into_a_locked_active_intent_dir
    activate_intent_27
    acquire_lease("other")
    cmd = "ruby -e 'File.write(#{File.join(@intent_dir, 'spec.md').inspect}, \"x\")'"
    reason = Bridge.bash_gate_decision(nil, cmd, cwd: "/", session: "sess-1")
    refute_nil reason
    assert_includes reason, "plastic-lock"
  end

  def test_bash_gate_allows_the_lock_owner
    activate_intent_27
    acquire_lease("sess-1")
    cmd = "ruby -e 'File.write(#{File.join(@intent_dir, 'spec.md').inspect}, \"x\")'"
    assert_nil Bridge.bash_gate_decision(nil, cmd, cwd: "/", session: "sess-1")
  end

  # --- escape tag -------------------------------------------------------------

  def test_trailing_plastic_ok_is_an_escape
    assert Bridge.bash_escape?("ruby -e 'File.write(\"/x\", 1)' # plastic-ok")
    refute Bridge.bash_escape?("echo '# plastic-ok'"),
           "a quoted occurrence is not a trailing comment"
    refute Bridge.bash_escape?("ruby -e 'x' # plastic-ok && rm x"),
           "the tag must END the command"
  end

  # --- hook-level escape audit (spawns the real hook) --------------------------

  HOOK = File.expand_path("../scripts/hook-bash-gate", __dir__)

  def test_hook_escape_allows_and_audits
    tmp = Dir.mktmpdir("bash-gate-hook-tmp")
    payload = { "tool_input" => { "command" => "echo x > /etc/motd # plastic-ok" },
                "cwd" => @cwd, "session_id" => "sess-esc" }
    _out, _err, status = Open3.capture3(
      { "HOME" => @home, "PLASTIC_TMP" => tmp, "CLAUDE_CODE_SESSION_ID" => nil },
      RbConfig.ruby, HOOK, stdin_data: JSON.generate(payload)
    )
    assert status.success?, "a plastic-ok command must be allowed"
    log = File.join(@home, ".plastic", ".cache", "gate-escapes.log")
    assert File.exist?(log), "the escape must be audited"
    assert_includes File.read(log), "sess-esc"
  ensure
    FileUtils.rm_rf(tmp)
  end
end
