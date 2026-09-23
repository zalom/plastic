# frozen_string_literal: true

require "varar"
require "tmpdir"
require_relative "support/public_command"

module ClosureAcceptance
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
      @command = PublicCommand.new(home)
      @global = @command.global
    end

    def plastic(*args)
      @command.run(*args).first
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
