# frozen_string_literal: true

require "varar"
require_relative "support/kernel_command"

module IntentEndAcceptance
  SESSION = { "PLASTIC_SESSION" => "end-walk" }.freeze
  OPTIONS = ["--judge", "tool", "--evidence", "completion.json"].freeze

  def self.build(kernel)
    kernel.run!("intent", "new", "Alpha", env: SESSION)
    kernel.write("store/1--alpha/spec.md", "# Spec\n## Done criteria\n- Ships\n")
    kernel.write("store/1--alpha/outcome.md", "# Outcome\nVerified the delivery.\n")
    kernel.run!("sync", "up", env: SESSION)
    kernel.run!("auto", "1", env: SESSION)
    kernel.run!("node", "add", "1", "Ship", "--criterion", "Ships", env: SESSION)
    kernel.run!("node", "claim", "1", "n1", env: SESSION)
    kernel.run!("node", "done", "1", "n1", "--judge", "tool", "--findings", "Fixture verification passed", env: SESSION)
    kernel.write("store/1--alpha/completion.json", JSON.generate({ "Ships" => "Fixture acceptance verified" }))
  end

  def self.call(kind)
    Dir.mktmpdir("varar-intent-end") do |home|
      kernel = KernelCommand.copied(home, :endable) { |built| build(built) }
      kernel.write("store/1--alpha/completion.json", "{}") if kind == "missing criterion evidence"
      kernel.run!("intent", "end", "1", *OPTIONS, env: SESSION) if kind == "repeat closure"
      options = (kind == "request verification" || kind == "repeat closure") ? [] : OPTIONS
      result = kernel.run("intent", "end", "1", *options, env: SESSION)
      cells(kernel, result)
    end
  end

  def self.cells(kernel, result)
    status = kernel.rows("work_graph.db", "SELECT status FROM intents WHERE intent_id = '1'").flatten.first
    count = kernel.rows("work_graph.db", "SELECT COUNT(*) FROM completions").flatten.first
    { "exit" => result.code.to_s, "status" => status, "completion records" => count.to_s,
      "next line" => (result.out.lines.grep(/^next:/).first || "next: none").strip.delete_prefix("next: ") }
  end
end

steps do
  sensor("the closure case, the exit code, the status, the completion records and the next line") do |_state, row|
    row.merge(IntentEndAcceptance.call(row["closure case"]))
  end
end
