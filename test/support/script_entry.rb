# encoding: UTF-8
# frozen_string_literal: true

require "stringio"

# A shared in-process entry point for the bare, extensionless scripts under
# scripts/ (new-intent, restore-intent-v1, and siblings): `load` the script
# into an anonymous module instead of the top level, so its bare `def main`
# and neighboring top-level methods never land on Object and collide with
# another such script's same-named method inside the full suite's one
# shared process. The script's own `if $PROGRAM_NAME == __FILE__` guard
# never fires this way (intentionally: that check compares the full
# suite's $PROGRAM_NAME against the loaded file, never a match), so the
# caller names the guarded method to invoke directly instead. These scripts
# are being replaced by the plastic command stage by stage, so this helper
# adds nothing to any of them beyond letting a test drive the existing
# entry point without a trailing interpreter spawn (intent 397, D6).
module ScriptEntry
  # A fake Process::Status: exitstatus plus the success? check callers read.
  FakeExitStatus = Struct.new(:exitstatus) do
    def success? = exitstatus.zero?
  end

  def self.call(script_path, method, *args, argv: [])
    runner = Object.new.extend(Module.new.tap { |mod| load(script_path, mod) })
    out, err, exit_code = capture_stdio(argv) { runner.send(method, *args) }
    [out + err, FakeExitStatus.new(exit_code)]
  end

  def self.capture_stdio(argv)
    out = StringIO.new
    err = StringIO.new
    original = swap_io(out, err, argv)
    exit_code = exit_code_of { yield }
    [out.string, err.string, exit_code]
  ensure
    restore_io(original)
  end
  private_class_method :capture_stdio

  def self.swap_io(out, err, argv)
    original = [$stdout, $stderr, ARGV.dup]
    $stdout = out
    $stderr = err
    ARGV.replace(argv)
    original
  end
  private_class_method :swap_io

  def self.restore_io(original)
    $stdout, $stderr, saved_argv = original
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
