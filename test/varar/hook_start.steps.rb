# frozen_string_literal: true

require "varar"
require "json"
require "tmpdir"
require_relative "support/kernel_command"

steps do
  sensor("the source, the session, the exit code, the first line, the names and the harness") do |_state, row|
    Dir.mktmpdir("varar-session-resume") do |home|
      kernel = KernelCommand.new(home)
      session = { "CLAUDE_CODE_SESSION_ID" => "s-1" }
      kernel.run!("hook", "start", input: JSON.generate(source: "startup"), env: session)
      kernel.run!("intent", "new", "Alpha", env: session)
      kernel.run!("intent", "new", "Beta", env: session)
      kernel.run!("session", "note", "stopped", "after", "Beta", env: session)
      if row["session"] != "s-1"
        kernel.run!("hook", "end", input: JSON.generate(reason: "clear"), env: session)
        session = { "CLAUDE_CODE_SESSION_ID" => row["session"] }
      end
      call = kernel.run("hook", "start", input: JSON.generate(source: row["source"]), env: session)
      names = %w[Alpha Beta] + ["intent new", "stopped after Beta"]
      row.merge("exit" => call.code.to_s, "first line" => call.out.lines(chomp: true).first.to_s,
        "names" => names.select { |name| call.out.include?(name) }.join(", "),
        "harness" => kernel.rows("../../local.db", "SELECT session_id, harness FROM sessions").to_h.fetch(row["session"]).to_s)
    end
  end
end
