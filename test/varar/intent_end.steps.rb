# frozen_string_literal: true

require "varar"
require_relative "support/kernel_command"

module IntentEndAcceptance
  SESSION = { "PLASTIC_SESSION" => "end-walk" }.freeze
  VERIFIED = "# Outcome\nVerified the delivery.\n\n## Verification\n- Merged: plastic/1 into alpha at abc123\n- Architecture map: enola at abc123\n- Pull request: https://example.test/pull/1\n- Approved: the owner on 2026-10-05\n"

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
  end

  def self.call(kind)
    Dir.mktmpdir("varar-intent-end") do |home|
      kernel = KernelCommand.copied(home, :endable) { |built| build(built) }
      cells(kernel, run(kernel, kind))
    end
  end

  def self.run(kernel, kind)
    withhold_merge_record(kernel) if kind == "unverified close"
    judge(kernel, "accept") unless kind == "request verification"
    kernel.run!("intent", "end", "1", env: SESSION) if kind == "repeat closure"
    kernel.run("intent", "end", "1", env: SESSION)
  end

  def self.judge(kernel, verdict)
    kernel.run!("intent", "judge", "1", "--verdict", verdict, "--findings", "Reviewed the delivery", env: SESSION)
  end

  def self.withhold_merge_record(kernel)
    kernel.write("store/1--alpha/outcome.md", "# Outcome\nVerified the delivery.\n\n## Verification\n- Pull request: https://example.test/pull/1\n- Approved: the owner on 2026-10-05\n")
    kernel.run!("sync", "up", env: SESSION)
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
