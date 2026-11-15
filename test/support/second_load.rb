# frozen_string_literal: true

# A second load of a source file, run in a forked copy of the test process. A load in
# the process that runs the suite would reset the coverage counts of that file and warn
# about each constant it defines again; the fork leaves both untouched. The block runs
# in the fork after the load, and its answer comes back as the exit status of the fork.
module SecondLoad
  def self.keeps?(path)
    pid = fork do
      $VERBOSE = nil
      kept = answer { load(path) && yield }
      exit!(kept ? 0 : 1)
    end
    Process.wait2(pid).last.success?
  end

  def self.answer
    yield
  rescue StandardError, ScriptError
    false
  end
  private_class_method :answer
end
