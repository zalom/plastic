# frozen_string_literal: true

require "varar"
require "json"
require "tmpdir"
require_relative "support/kernel_command"

steps do
  sensor("the notes, the session, the exit code, the result and the note line") do |_state, row|
    Dir.mktmpdir("varar-session-note") do |home|
      kernel = KernelCommand.new(home)
      opened = { "CLAUDE_CODE_SESSION_ID" => "s-1" }
      kernel.run!("hook", "resume", input: JSON.generate(source: "startup"), env: opened)
      env = (row["session"] == "none") ? {} : { "CLAUDE_CODE_SESSION_ID" => row["session"] }
      notes = (row["notes"] == "(none)") ? [nil] : row["notes"].split(", ")
      calls = notes.map { |note| kernel.run("session", "note", *note&.split, env:) }
      resume = kernel.run("hook", "resume", input: JSON.generate(source: "clear"), env: opened)
      row.merge("exit" => calls.last.code.to_s, "result" => calls.map(&:result).join(" / "),
        "note line" => resume.out.lines(chomp: true).grep(/\Anote: /).first || "none")
    end
  end
end
