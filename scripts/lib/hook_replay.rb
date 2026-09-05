# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "open3"
require "timeout"

# HookReplay (intent 331a, T1; promoted to a production lib in 331e) - streams
# text through a MessageDisplay launcher the way Claude Code streams an
# assistant reply, chunk by chunk, and returns every chunk's raw stdout.
#
# 331a's test/support/hook_replay.rb held this as test-only code; 331e's
# doctor `display_hook_paints` check (scripts/doctor.rb) needs the exact same
# mechanics to replay the INSTALLED launcher for real, so the logic lives
# here and test/support/hook_replay.rb now delegates to it (a require, not a
# duplicate). Never require this from scripts/lib/doctor_core.rb: that file
# is the SessionStart boot path (test/doctor_core_split_test.rb T2 pins its
# exact require set), and the paint check that needs this lib runs only from
# the full scripts/doctor.rb.
module HookReplay
  module_function

  # Streams `text` through `hook_path` in fixed-size chunks. `session_id`/
  # `message_id` default to fixed values since nothing about a replay depends
  # on the ambient session at all.
  #
  # `env` (intent 331e): extra child-process environment, merged over the
  # PLASTIC_TMP entry every call already sets (a caller's own key wins). A
  # `nil` value unsets that variable in the child (Process.spawn's own
  # convention) — how a caller forces NO_COLOR off regardless of the ambient
  # environment. Default `{}` keeps every existing caller's behavior
  # unchanged: this is an extension, not a fork.
  #
  # `timeout` (intent 331e): when given, bounds EACH chunk's spawn to that
  # many seconds. A bare `Timeout.timeout` around `Open3.capture3` does not
  # reliably bound a genuinely hanging child — capture3's own wait still
  # blocks on Process.waitpid for the child regardless of the raised
  # Timeout::Error (the same gotcha scripts/hook-record works around) — so a
  # timeout here spawns directly and kills the child on expiry instead.
  # Default `nil` keeps every existing caller on the original unbounded
  # Open3.capture3 path.
  def replay(hook_path:, tmp_root:, text:, chunk: 40, session_id: "s-replay", message_id: "replay",
              env: {}, timeout: nil)
    chunks = text.scan(/.{1,#{chunk}}/m)
    chunks = [""] if chunks.empty?
    full_env = { "PLASTIC_TMP" => tmp_root }.merge(env)

    chunks.each_with_index.map do |delta, i|
      payload = {
        "session_id" => session_id, "message_id" => message_id, "index" => i,
        "final" => i == chunks.length - 1, "delta" => delta, "cwd" => tmp_root,
        "hook_event_name" => "MessageDisplay",
      }
      out, err, exitstatus = run_one(hook_path, payload, full_env, tmp_root, timeout)
      { index: i, exitstatus: exitstatus, stdout: out, stderr: err, final: payload["final"] }
    end
  end

  def run_one(hook_path, payload, full_env, tmp_root, timeout)
    return capture(hook_path, payload, full_env) unless timeout

    run_bounded(hook_path, payload, full_env, tmp_root, timeout)
  end

  def capture(hook_path, payload, full_env)
    out, err, status = Open3.capture3(full_env, hook_path, stdin_data: JSON.generate(payload))
    [out, err, status.exitstatus]
  end

  # Spawn directly (never Open3.capture3) so a timeout can actually kill the
  # child, with stdin/stdout/stderr routed through scratch files under the
  # caller's own tmp_root — never pipes, so a stalled or oversized write can
  # never deadlock the read side, and never anywhere outside tmp_root, so a
  # bounded replay carries the same "writes only under the injected tmp
  # root" guarantee as the unbounded path.
  def run_bounded(hook_path, payload, full_env, tmp_root, timeout)
    token = "#{Process.pid}-#{(Time.now.to_f * 1_000_000).to_i}-#{rand(1_000_000)}"
    in_path = File.join(tmp_root, ".hook-replay-in-#{token}")
    out_path = File.join(tmp_root, ".hook-replay-out-#{token}")
    err_path = File.join(tmp_root, ".hook-replay-err-#{token}")
    File.write(in_path, JSON.generate(payload))

    pid = Process.spawn(full_env, hook_path, in: in_path, out: out_path, err: err_path)
    exitstatus =
      begin
        Timeout.timeout(timeout) { Process.wait(pid) }
        $?.exitstatus
      rescue Timeout::Error
        kill_and_reap(pid)
        nil # nil exitstatus is the caller's signal that this chunk timed out
      end

    out = File.exist?(out_path) ? File.read(out_path) : ""
    err = File.exist?(err_path) ? File.read(err_path) : ""
    [out, err, exitstatus]
  ensure
    [in_path, out_path, err_path].each { |p| File.delete(p) if p && File.exist?(p) }
  end

  def kill_and_reap(pid)
    Process.kill("KILL", pid)
  rescue StandardError
    nil
  ensure
    begin
      Process.wait(pid)
    rescue StandardError
      nil
    end
  end

  # The final chunk's parsed displayContent, or nil when it emitted nothing
  # (no envelope at all: the message never engaged).
  def final_display_content(outs)
    final = outs.last
    return nil if final[:stdout].to_s.empty?

    JSON.parse(final[:stdout]).dig("hookSpecificOutput", "displayContent")
  rescue JSON::ParserError
    nil
  end

  # True when any chunk's spawn hit its timeout (run_bounded's nil-exitstatus
  # signal). A replay made with no `timeout:` never reports true.
  def timed_out?(outs)
    outs.any? { |o| o[:exitstatus].nil? }
  end
end
