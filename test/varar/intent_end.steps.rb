# frozen_string_literal: true

require "varar"
require_relative "support/kernel_command"

module IntentEndAcceptance
  SESSION = { "PLASTIC_SESSION" => "end-walk" }.freeze
  VERIFIED = "# Outcome\nVerified the delivery.\n\n## Verification\n- Merged: plastic/1 into alpha at abc123\n- Architecture map: enola at abc123\n- Pull request: https://example.test/pull/1\n- Approved: the owner on 2026-10-05\n"

  def self.build(kernel)
    kernel.command!("intent", "new", "Alpha", env: SESSION)
    kernel.write("store/1--alpha/spec.md", "# Spec\n## Done criteria\n- [ ] [ships] Ships\n")
    kernel.write("store/1--alpha/outcome.md", VERIFIED)
    kernel.command!("sync", "up", env: SESSION)
    kernel.command!("intent", "approve", "1", env: SESSION)
    kernel.command!("auto", "1", env: SESSION)
    kernel.command!("node", "add", "1", "Ship", "--criterion", "ships", env: SESSION)
    kernel.command!("node", "claim", "1", "n1", env: SESSION)
    kernel.command!("node", "done", "1", "n1", "Fixture verification passed", env: SESSION)
  end

  def self.call(kind)
    Dir.mktmpdir("varar-intent-end") do |home|
      kernel = KernelCommand.copied(home, :endable) { |built| build(built) }
      cells(kernel, end_intent(kernel, kind))
    end
  end

  def self.end_intent(kernel, kind)
    withhold_merge_record(kernel) if kind == "unverified close"
    judge(kernel, "accept") unless kind == "request verification"
    kernel.command!("intent", "end", "1", env: SESSION) if kind == "repeat closure"
    kernel.command("intent", "end", "1", env: SESSION)
  end

  def self.judge(kernel, verdict)
    kernel.command!("intent", "verdict", "1", verdict, "Reviewed the delivery", env: SESSION)
  end

  def self.withhold_merge_record(kernel)
    kernel.write("store/1--alpha/outcome.md", "# Outcome\nVerified the delivery.\n\n## Verification\n- Pull request: https://example.test/pull/1\n- Approved: the owner on 2026-10-05\n")
    kernel.command!("sync", "up", env: SESSION)
  end

  def self.cells(kernel, result)
    status = kernel.rows("work_graph.db", "SELECT status FROM intents ORDER BY CAST(intent_id AS INTEGER) DESC LIMIT 1").flatten.first
    count = kernel.rows("work_graph.db", "SELECT COUNT(*) FROM completions").flatten.first
    { "exit" => result.code.to_s, "status" => status, "completion records" => count.to_s,
      "next line" => result.out.lines.grep(/^next:/).first&.strip&.delete_prefix("next: ") || "no next line" }
  end
end

steps do
  sensor("the closure case, the exit code, the status, the completion records and the next line") do |_state, row|
    row.merge(IntentEndAcceptance.call(row["closure case"]))
  end
end
