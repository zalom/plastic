# frozen_string_literal: true

require "varar"
require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

# Runs the repository's own bin/plastic against a disposable home: HOME,
# PLASTIC_HOME and PLASTIC_TMP all point inside a temporary directory.
module ClosureAcceptance
  PLASTIC = File.expand_path("../../bin/plastic", __dir__)

  HOLLOW_OUTCOME = <<~MD
    ---
    disposition: delivered
    ---
    # Outcome: demo

    ## Delivered
    - D1 something shipped

    ## Needs you
    None
  MD

  class Scenario
    def initialize(home)
      @home = home
      @global = File.join(home, ".plastic", "stores", "global")
      FileUtils.mkdir_p(File.join(@global, "store"))
      File.write(File.join(@global, "INDEX.md"), "# Index\n\n## Active\n\n## Completed\n\n## Abandoned\n")
      @env = {"HOME" => home, "PLASTIC_HOME" => File.join(home, ".plastic"), "PLASTIC_TMP" => File.join(home, "tmp"),
              "CLAUDE_CODE_SESSION_ID" => nil, "RUBYOPT" => nil, "BUNDLER_SETUP" => nil,
              "GIT_CONFIG_GLOBAL" => File.join(home, ".gitconfig"), "GIT_CONFIG_SYSTEM" => "/dev/null"}
    end

    def plastic(*args)
      _out, _err, status = Open3.capture3(@env, RbConfig.ruby, PLASTIC, *args, chdir: @home)
      status.exitstatus
    end

    def run(row)
      plastic("intent", "new", "demo work", "--slug", "demo")
      record(row.fetch("record"), File.join(@global, "store", "1--demo"))
      args = ["intent", "end", "1", "--delivered", "--summary", "demo summary"]
      args << "--dry-run" if row.fetch("mode") == "preview"
      code = plastic(*args)
      row.merge("exit" => code.to_s, "index section" => section)
    end

    def record(kind, dir)
      case kind
      when "worked"
        File.write(File.join(dir, "checklist.md"), "# Checklist: demo\n\n- [x] S1 the change\n")
      when "hollow report"
        File.write(File.join(dir, "actions", "ACTION_1.md"), "# ACTION_1\n\n### S1 - the thing\n")
        File.write(File.join(dir, "outcome.md"), HOLLOW_OUTCOME)
      end
    end

    def section
      heading = nil
      File.foreach(File.join(@global, "INDEX.md")) do |line|
        heading = line.delete_prefix("## ").strip if line.start_with?("## ")
        return heading if line.include?("1--demo")
      end
      "none"
    end
  end
end

steps do
  sensor("the record, the mode, the exit and the index section") do |_state, row|
    Dir.mktmpdir("varar-closure") { |home| ClosureAcceptance::Scenario.new(home).run(row) }
  end
end
