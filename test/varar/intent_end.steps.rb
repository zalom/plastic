# frozen_string_literal: true

require "varar"
require_relative "support/kernel_command"

module IntentEndAcceptance
  SESSION = { "PLASTIC_SESSION" => "end-walk" }.freeze
  OPTIONS = ["--judge", "tool", "--evidence", "completion.json"].freeze
  VERIFIED = "# Outcome\nVerified the delivery.\n\n## Verification\n- Merged: plastic/1 into alpha at abc123\n- Architecture map: enola at abc123\n"
  BARE = ["request verification", "repeat closure"].freeze

  def self.build(kernel)
    kernel.run!("intent", "new", "Alpha", env: SESSION)
    kernel.write("store/1--alpha/spec.md", "# Spec\n## Done criteria\n- [ ] [ships] Ships\n")
    kernel.write("store/1--alpha/outcome.md", VERIFIED)
    kernel.run!("sync", "up", env: SESSION)
    kernel.run!("intent", "approve", "1", env: SESSION)
    kernel.run!("auto", "1", env: SESSION)
    kernel.run!("node", "add", "1", "Ship", "--criterion", "ships", env: SESSION)
    kernel.run!("node", "claim", "1", "n1", env: SESSION)
    kernel.run!("node", "done", "1", "n1", "--findings", "Fixture verification passed", env: SESSION)
    kernel.write("store/1--alpha/completion.json", JSON.generate({ "ships" => "Fixture acceptance verified" }))
  end

  def self.call(kind)
    Dir.mktmpdir("varar-intent-end") do |home|
      kernel = KernelCommand.copied(home, :endable) { |built| build(built) }
      cells(kernel, run(kernel, kind))
    end
  end

  def self.run(kernel, kind)
    return abandon(kernel) if kind == "abandon"

    kernel.write("store/1--alpha/completion.json", "{}") if kind == "missing criterion evidence"
    withhold_merge_record(kernel) if kind == "unverified close"
    kernel.run!("intent", "end", "1", *OPTIONS, env: SESSION) if kind == "repeat closure"
    kernel.run("intent", "end", "1", *(BARE.include?(kind) ? [] : OPTIONS), env: SESSION)
  end

  def self.withhold_merge_record(kernel)
    kernel.write("store/1--alpha/outcome.md", "# Outcome\nVerified the delivery.\n")
    kernel.run!("sync", "up", env: SESSION)
  end

  def self.abandon(kernel)
    kernel.run!("intent", "new", "Beta", env: SESSION)
    kernel.write("store/2--beta/outcome.md", "# Outcome\nDropped: the need went away.\n")
    kernel.run!("sync", "up", env: SESSION)
    kernel.run("intent", "end", "2", "--abandoned", env: SESSION)
  end

  def self.cells(kernel, result)
    status = kernel.rows("work_graph.db", "SELECT status FROM intents ORDER BY CAST(intent_id AS INTEGER) DESC LIMIT 1").flatten.first
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
