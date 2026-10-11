# frozen_string_literal: true

require "varar"
require "json"
require "tmpdir"
require_relative "support/kernel_command"

steps do
  sensor("the arguments, the event, the session, the exit code, the message and the row") do |_state, row|
    Dir.mktmpdir("varar-hook-stop") do |home|
      kernel = KernelCommand.new(home)
      kernel.run!("hook", "start", input: JSON.generate(source: "startup"), env: { "CLAUDE_CODE_SESSION_ID" => "s-1" })
      env = (row["session"] == "none") ? {} : { "CLAUDE_CODE_SESSION_ID" => row["session"] }
      arguments = (row["arguments"] == "(none)") ? [] : row["arguments"].split
      call = kernel.run("hook", "stop", *arguments, input: row["event"], env:)
      sessions = kernel.rows("../../local.db", "SELECT session_id, harness, last_turn_at, ended_at, end_reason FROM sessions")
      id, harness, turn, ended, reason = sessions.find { |session| session[0] == (env.empty? ? "s-1" : row["session"]) }
      shown = "#{id} #{harness || "no harness"}, #{turn ? "turn stamped" : "no turn"}, #{ended ? "ended #{reason}" : "open"}"
      row.merge("exit" => call.code.to_s, "message" => call.err.strip.empty? ? "none" : call.err.strip.tr("\n", " "), "row" => shown)
    end
  end
end
