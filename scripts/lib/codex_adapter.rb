# encoding: UTF-8
# frozen_string_literal: true

require "yaml"
require "timeout"
require "tmpdir"
require_relative "runner_policy"

# CodexAdapter (intent 340b, G7c, n6): the argv `codex exec` needs for one
# node's kind, and the mechanics of running it once - a bounded subprocess
# whose stdin carries the node input, whose stdout and `--output-last-message`
# file are the only two places a return can come from, and whose timeout
# kills the whole process group rather than one pid.
#
# Pure where it can be: sandbox_mode, git_dir_for_worktree, add_dir_args and
# build_argv touch nothing but the filesystem read they are explicitly given
# (the worktree's own `.git` file), never a git call and never a guess at a
# repository root. #execute is the one place this module actually spawns a
# child process; scripts/node-run is the only caller.
module CodexAdapter
  module_function

  # Verify and research get NO write access at all (spec D9): read-only, no
  # `--add-dir`. Everything else - work, and any kind this table has never
  # heard of - gets the widest treatment, matching RunnerPolicy's own
  # unknown-kind-falls-back-to-work rule (matrix row 6.10).
  READ_ONLY_KINDS = %w[verify research].freeze

  def sandbox_mode(kind)
    READ_ONLY_KINDS.include?(kind.to_s) ? "read-only" : "workspace-write"
  end

  # The repository's OWN `.git` directory, derived from `worktree`'s `.git`
  # FILE (a git worktree never carries a real `.git` directory of its own -
  # spec) rather than any guess at how many path segments separate a
  # worktree from its repo (matrix row 6.6). `.git` reads
  # `gitdir: <repo>/.git/worktrees/<name>`; two directories up from that
  # target is the repository's real `.git`. Returns nil when `worktree` is
  # not a git worktree at all (no `.git` file, or `.git` is a directory,
  # meaning `worktree` is a repository's own primary checkout) - callers
  # treat that as "no `--add-dir` to add", never as a reason to guess.
  def git_dir_for_worktree(worktree)
    gitfile = File.join(worktree.to_s, ".git")
    return nil unless File.file?(gitfile)

    content = File.read(gitfile)
    m = content.match(/\Agitdir:\s*(.+?)\s*\z/m)
    return nil unless m

    worktrees_entry = File.expand_path(m[1], worktree.to_s)
    File.dirname(File.dirname(worktrees_entry))
  end

  # [] for a read-only kind (matrix row 6.4): `-C` already makes the
  # worktree writable, and `--add-dir` on top of `--sandbox read-only` would
  # contradict the sandbox mode itself. Exactly one `--add-dir`, the
  # repository's own `.git`, for every other kind (matrix row 6.5) - nil
  # when the worktree's own gitdir pointer cannot be resolved, so a caller
  # handed a plain (non-worktree) directory never gets a bogus argument.
  def add_dir_args(kind:, worktree:)
    return [] if READ_ONLY_KINDS.include?(kind.to_s)

    git_dir = git_dir_for_worktree(worktree)
    git_dir ? ["--add-dir", git_dir] : []
  end

  # The whole `codex exec` argv for one node (matrix rows 6.1-6.9): `-C` at
  # the worktree given (row 6.8), the sandbox mode and `--add-dir` this
  # kind's row calls for and nothing else (row 6.7 - never the intent
  # worktree, never `~/.plastic`), `--output-last-message` at the path the
  # caller names, and a bare `-` so the prompt is read from stdin (row 6.9) -
  # the node input itself never rides in this array.
  def build_argv(kind:, worktree:, output_last_message:)
    [
      "codex", "exec",
      "-C", worktree.to_s,
      "--sandbox", sandbox_mode(kind),
      *add_dir_args(kind: kind, worktree: worktree),
      "--output-last-message", output_last_message.to_s,
      "-",
    ]
  end

  # matrix row 6.23: the wall-clock bound comes from the KIND's own lease
  # length (RunnerPolicy.lease_minutes), never one shared constant - a long
  # `work` build must not be capped as tightly as a quick `verify` pass.
  def timeout_seconds(kind)
    RunnerPolicy.lease_minutes(kind) * 60
  end

  # The return text (matrix rows 6.18/6.19): `output_last_message_path`'s
  # own content when it exists and is non-blank (row 6.18 - stdout is never
  # even inspected on this path), else the last YAML document found in
  # `stdout` (row 6.19), else nil (no return anywhere - row 6.20 is the
  # caller's problem, not this method's).
  def read_return(output_last_message_path:, stdout:)
    from_file = file_present_content(output_last_message_path)
    return from_file unless from_file.nil?

    stdout_fallback(stdout)
  end

  # The LAST YAML document in `text` that parses to a mapping, or nil when
  # none does (row 6.20's other half). Documents are separated the ordinary
  # YAML way, a line holding only `---`; a stream with no such separator at
  # all is treated as one candidate document. Every candidate is tried from
  # the end, so three documents (one row names explicitly) still resolve to
  # the last one, and prose or a fragment that never parses to a mapping is
  # skipped rather than returned as the "document".
  def stdout_fallback(text)
    return nil if text.to_s.strip.empty?

    segments = text.to_s.split(/^---[ \t]*$/m).map(&:strip).reject(&:empty?)
    segments = [text.to_s.strip] if segments.empty?

    segments.reverse_each do |segment|
      return segment if safe_yaml(segment).is_a?(Hash)
    end
    nil
  end

  # Runs `argv` once, feeding `stdin_data` on stdin through a scratch file
  # (never a pipe - the same "never deadlock the read side" reasoning
  # HookReplay.run_bounded already carries), bounded to `timeout_seconds`.
  # `argv`'s own child becomes its own process group (`pgroup: true`) so a
  # timeout can kill every child `codex exec` spawned along the way, not
  # just the pid this call started (matrix row 6.24) - `codex exec` itself
  # spawns shells for the commands it runs, and those would otherwise
  # outlive a plain `Process.kill` on the parent alone, holding the
  # worktree.
  #
  # Returns {exit_code:, timed_out:, stdout:, message:}. `message` is
  # #read_return's result, computed only when the call did not time out - a
  # timed-out child's partial output is never trusted (matrix row 6.22).
  def execute(argv, stdin_data:, timeout_seconds:, output_last_message_path:)
    Dir.mktmpdir("plastic-node-run-") do |scratch|
      in_path = File.join(scratch, "stdin")
      out_path = File.join(scratch, "stdout")
      err_path = File.join(scratch, "stderr")
      File.binwrite(in_path, stdin_data.to_s)

      pid = Process.spawn(*argv.map(&:to_s), in: in_path, out: out_path, err: err_path, pgroup: true)
      timed_out = false
      exit_code =
        begin
          Timeout.timeout(timeout_seconds) do
            Process.wait(pid)
            $?.exitstatus
          end
        rescue Timeout::Error
          timed_out = true
          kill_group(pid)
          nil
        end

      stdout = File.exist?(out_path) ? File.read(out_path) : ""
      message = timed_out ? nil : read_return(output_last_message_path: output_last_message_path, stdout: stdout)

      { exit_code: exit_code, timed_out: timed_out, stdout: stdout, message: message }
    end
  end

  # --- internals ---------------------------------------------------------------

  def file_present_content(path)
    return nil if path.nil? || !File.exist?(path)

    content = File.read(path)
    content.strip.empty? ? nil : content
  end
  private_class_method :file_present_content

  def safe_yaml(text)
    YAML.safe_load(text, aliases: false, permitted_classes: [])
  rescue Psych::Exception, ArgumentError
    nil
  end
  private_class_method :safe_yaml

  # Kills the whole process GROUP `pid` leads, not just `pid` itself (matrix
  # row 6.24): a negative pid signals the group. Rescued and reaped exactly
  # like HookReplay.kill_and_reap - a process that exited in the race
  # between the timeout firing and this call raises Errno::ESRCH on the kill
  # or Errno::ECHILD on the wait, neither of which should ever propagate.
  def kill_group(pid)
    Process.kill("KILL", -pid)
  rescue StandardError
    nil
  ensure
    begin
      Process.wait(pid)
    rescue StandardError
      nil
    end
  end
  private_class_method :kill_group
end
