require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../scripts/lib/hook_replay"

# HookReplay's bounded path (doctor display_hook_paints, acceptance N9). It
# used scratch files for the child's stdin and stdout, and on Snap Ruby the
# launcher's `ruby` could not use them: every chunk came back empty with
# exit 1. The bounded path now uses pipes, like the unbounded one, while
# keeping the timeout, the process cleanup and large outputs.
class HookReplayBoundedTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir("hook-replay-bounded")
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def hook(body)
    path = File.join(@tmp, "hook-#{rand(1_000_000)}")
    File.write(path, "#!/bin/bash\n#{body}\n")
    File.chmod(0o755, path)
    path
  end

  def run_bounded(path, timeout: 10, payload: {"probe" => "expected"})
    HookReplay.run_one(path, payload, {"RUBYOPT" => nil, "BUNDLER_SETUP" => nil}, @tmp, timeout)
  end

  def test_stdin_reaches_a_ruby_child_and_its_stdout_comes_back
    path = hook(%(IFS= read -r -d '' INPUT\nprintf '%s' "$INPUT" | ruby -e 'STDERR.print "err"; print STDIN.read'))

    assert_equal ['{"probe":"expected"}', "err", 0], run_bounded(path)
  end

  def test_multibyte_output_comes_back_as_text
    out, _err, status = run_bounded(hook("cat >/dev/null\nfor i in $(seq 40000); do printf '\\342\\226\\266'; done"))

    assert_equal [Encoding.default_external, 40_000, 0], [out.encoding, out.each_char.count { |c| c.ord == 0x25B6 }, status]
  end

  def test_the_exit_status_is_the_hooks_own
    assert_equal ["", "", 3], run_bounded(hook("cat >/dev/null\nexit 3"))
  end

  def test_a_hook_that_never_reads_stdin_still_returns
    assert_equal ["done", "", 0], run_bounded(hook("printf done"), payload: {"delta" => "x" * 200_000})
  end

  def test_large_stdout_and_stderr_come_back_whole
    path = hook("cat >/dev/null\nhead -c 1048576 /dev/zero | tr '\\0' o\nhead -c 1048576 /dev/zero | tr '\\0' e >&2")

    out, err, status = run_bounded(path)

    assert_equal [1_048_576, 1_048_576, 0], [out.bytesize, err.bytesize, status]
  end

  def test_a_timeout_returns_nil_and_kills_the_whole_process_group
    pid_file = File.join(@tmp, "grandchild.pid")
    path = hook("sleep 4 &\necho $! > #{pid_file}\nwait")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    _out, _err, status = run_bounded(path, timeout: 1)

    assert_nil status
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
    refute alive?(File.read(pid_file).to_i), "the hook's own child must not outlive the timeout"
  end

  def test_an_exited_launcher_whose_child_keeps_the_pipes_is_still_bounded
    pid_file = File.join(@tmp, "descendant.pid")
    path = hook("cat >/dev/null\nprintf partial\nsleep 4 &\necho $! > #{pid_file}\nexit 0")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    out, _err, status = run_bounded(path, timeout: 0.5)

    assert_equal ["partial", nil], [out, status]
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
    refute alive?(File.read(pid_file).to_i), "the descendant must not outlive the timeout"
  end

  def test_a_hook_that_stalls_before_reading_a_large_payload_is_bounded
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    _out, _err, status = run_bounded(hook("sleep 4\ncat >/dev/null"), timeout: 0.5,
      payload: {"delta" => "x" * 1_048_576})

    assert_nil status
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
  end

  def test_killing_a_group_that_already_exited_is_quiet
    pid = Process.spawn("true", pgroup: true)
    Process.wait(pid)

    assert_nil HookReplay.kill_group(pid)
  end

  def test_the_bounded_path_writes_nothing_under_tmp_root
    path = hook("cat >/dev/null\nprintf ok")
    before = Dir.children(@tmp)

    run_bounded(path)

    assert_equal before, Dir.children(@tmp)
  end

  def test_replay_passes_the_timeout_through_to_every_chunk
    path = hook("cat >/dev/null\nprintf ok")

    outs = HookReplay.replay(hook_path: path, tmp_root: @tmp, text: "a" * 50, chunk: 40, timeout: 5)

    assert_equal [["ok", 0], ["ok", 0]], outs.map { |o| [o[:stdout], o[:exitstatus]] }
  end

  def alive?(pid)
    10.times do
      Process.kill(0, pid)
      sleep 0.1
    end
    true
  rescue Errno::ESRCH
    false
  end
end
