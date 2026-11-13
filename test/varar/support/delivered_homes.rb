# frozen_string_literal: true

require_relative "two_homes"

module DeliveredHomes
  include TwoHomes

  SESSION = {"PLASTIC_SESSION" => "delivery"}.freeze
  RECORDS = "- Merged: plastic/1 into alpha at abc123\n- Architecture map: enola at abc123\n" \
            "- Pull request: https://example.test/pull/1\n- Approved: the owner on 2026-10-05\n"
  OUTCOME = "# Outcome\n\nDelivered and verified.\n\n## Verification\n#{RECORDS}"
  DROPPED = "# Outcome\n\nDropped: the need went away.\n\n## Verification\n- Reverted: nothing delivered\n"

  def deliver(kernel)
    kernel.run!("auto", "1", env: SESSION)
    kernel.run!("node", "claim", "1", "n2")
    kernel.run!("node", "done", "1", "n2", "The code is green")
    kernel.run!("intent", "verdict", "1", "accept", "Both nodes hold")
    kernel.write("#{DIR}/outcome.md", OUTCOME)
    File.write(File.join(kernel.plastic_home, "config.yml"), "review:\n  pull_request: off\n")
    kernel.run!("sync", "up")
    kernel.run!("intent", "end", "1", env: SESSION)
    kernel.run!("sync", "down")
  end

  def abandon(kernel, number)
    kernel.write("store/#{number}--dropped/outcome.md", DROPPED)
    kernel.run!("sync", "up")
    kernel.run!("intent", "abandon", number, env: SESSION)
  end

  def with_homes(before_move)
    Dir.mktmpdir do |one|
      Dir.mktmpdir do |two|
        first, second = KernelCommand.new(one), KernelCommand.new(two)
        first_home(first)
        before_move.call(first)
        first.run!("sync", "down")
        move_files(first, second)
        yield first, second
      end
    end
  end
end
