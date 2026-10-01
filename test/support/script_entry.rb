# encoding: UTF-8
# frozen_string_literal: true

require "stringio"

# A shared in-process entry point for the bare, extensionless scripts under
# scripts/ (new-intent, restore-intent-v1, end-intent, hook-capture, and
# siblings): `load` the script into an anonymous module instead of the top
# level, so its bare `def main` (or, for a script with no main at all, its
# top-level statements) and neighboring top-level methods never land on
# Object and collide with another such script's same-named method inside the
# full suite's one shared process. The script's own
# `if $PROGRAM_NAME == __FILE__` guard never fires this way (intentionally:
# that check compares the full suite's $PROGRAM_NAME against the loaded
# file, never a match), so the caller names the guarded method to invoke
# directly instead - or, for a script that runs its logic as top-level
# statements with no wrapping method, leaves `method` nil and lets the load
# itself be the entry point. These scripts are being replaced by the
# plastic command stage by stage, so this helper adds nothing to any of
# them beyond letting a test drive the existing entry point without a
# trailing interpreter spawn (intent 397, D6).
module ScriptEntry
  # A fake Process::Status: exitstatus plus the success? check callers read.
  FakeExitStatus = Struct.new(:exitstatus) do
    def success? = exitstatus.zero?
  end

  # One merged stream for stdout and stderr, matching the IO.popen(...,
  # err: [:child, :out]) merge the subprocess-driving callers used: a script
  # that warns on stderr before printing its stdout result (new-intent's
  # dead-chain-ref diagnostic ahead of the scaffolded path) needs that
  # chronological order preserved, which two independently-captured buffers
  # concatenated after the fact cannot give back.
  def self.call(script_path, method = nil, *args, **opts)
    argv = opts.fetch(:argv, [])
    env = opts.fetch(:env, {})
    stdin = opts[:stdin]
    merged = StringIO.new
    exit_code = with_env(env) { capture_stdio(argv, stdin, out: merged, err: merged) { run_in_module(script_path, method, args) } }
    [merged.string, FakeExitStatus.new(exit_code)]
  end

  # Same load-into-a-module entry point as `call`, but keeping stdout and
  # stderr genuinely separate (matching Open3.capture3, which the callers
  # driving this way already called directly and so already read out/err
  # apart, with no merge-order expectation to preserve).
  def self.call3(script_path, method = nil, *args, **opts)
    capture3(**opts) { run_in_module(script_path, method, args) }
  end

  # The capture3-shaped primitive underneath `call`, exposed directly for a
  # script already loaded in process by its own real constant (e.g. a proper
  # `module Runner` loaded once by plain `load` at file top, whose CLI entry
  # is a module method such as `Runner.main`, not a bare top-level `def` that
  # needs the module-wrap load `call` does). The caller supplies the block
  # that invokes it; this method only supplies the env/stdio/exit capture.
  # Unlike `call`, stdout and stderr are genuinely separate streams here
  # (matching Open3.capture3), since a caller asking for them apart has
  # already said it does not need chronological interleaving.
  def self.capture3(argv: [], env: {}, stdin: nil)
    out = StringIO.new
    err = StringIO.new
    exit_code = with_env(env) { capture_stdio(argv, stdin, out: out, err: err) { yield } }
    [out.string, err.string, FakeExitStatus.new(exit_code)]
  end

  def self.run_in_module(script_path, method, args)
    mod = Module.new
    runner = Object.new.extend(mod)
    # A script this process already required once by its real path (a
    # shared lib/*.rb) and a copy of it loaded here from a second,
    # fixture path both define the same constants. The real subprocess
    # this replaces never saw that: each spawn got its own fresh
    # process, so the second definition warned at nobody. $VERBOSE off
    # for the load keeps that silence instead of leaking an
    # "already initialized constant" warning onto the captured stderr.
    quietly { load(script_path, mod) }
    runner.send(method, *args) if method
  end
  private_class_method :run_in_module

  def self.quietly
    original = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = original
  end
  private_class_method :quietly

  # Sets each env.each_pair for the duration of the block (a nil value
  # deletes the key, matching IO.popen's env-hash convention the scripts'
  # subprocess-driving callers already use), then restores the prior values.
  def self.with_env(env)
    original = env.keys.to_h { |key| [key, ENV[key]] }
    env.each_pair { |key, value| ENV[key] = value }
    yield
  ensure
    original.each_pair { |key, value| ENV[key] = value }
  end
  private_class_method :with_env

  def self.capture_stdio(argv, stdin, out:, err:)
    original = swap_io(out, err, argv, stdin)
    exit_code_of { yield }
  ensure
    restore_io(original)
  end
  private_class_method :capture_stdio

  def self.swap_io(out, err, argv, stdin)
    original = [$stdout, $stderr, $stdin, ARGV.dup]
    $stdout = out
    $stderr = err
    $stdin = StringIO.new(stdin) unless stdin.nil?
    ARGV.replace(argv)
    original
  end
  private_class_method :swap_io

  def self.restore_io(original)
    $stdout, $stderr, $stdin, saved_argv = original
    ARGV.replace(saved_argv)
  end
  private_class_method :restore_io

  def self.exit_code_of
    yield
    0
  rescue SystemExit => e
    e.status
  end
  private_class_method :exit_code_of
end
