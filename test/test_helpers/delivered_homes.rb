# frozen_string_literal: true

require_relative "two_homes"
require_relative "config_homes"

module DeliveredHomes
  include ConfigHomes

  include TwoHomes

  SESSION = { "PLASTIC_SESSION" => "delivery" }.freeze
  RECORDS = "- Merged: plastic/1 into alpha at abc123\n- Architecture map: enola at abc123\n" \
            "- Pull request: https://example.test/pull/1\n- Approved: the owner on 2026-10-05\n"
  OUTCOME = "# Outcome\n\nDelivered and verified.\n\n## Verification\n#{RECORDS}"
  DROPPED = "# Outcome\n\nDropped: the need went away.\n\n## Verification\n- Reverted: nothing delivered\n"

  def deliver(kernel)
    kernel.command!("intent", "auto", "1", env: SESSION)
    kernel.command!("node", "claim", "1", "n2", "--agent", "tester")
    kernel.command!("node", "done", "1", "n2", "The code is green")
    kernel.command!("intent", "verdict", "1", "accept", "Both nodes hold")
    kernel.write("#{DIR}/outcome.md", OUTCOME)
    seed_config(kernel.plastic_home, "review:\n  pull_request: off\n")
    kernel.command!("sync", "up")
    kernel.command!("intent", "end", "1", env: SESSION)
    kernel.command!("sync", "down")
  end

  def abandon(kernel, number)
    kernel.write("store/#{number}--dropped/outcome.md", DROPPED)
    kernel.command!("sync", "up")
    kernel.command!("intent", "abandon", number, env: SESSION)
  end

  def moved(first, second, before_move)
    first_home(first)
    before_move.call(first)
    first.command!("sync", "down")
    move_files(first, second)
  end

  def with_homes(before_move)
    Dir.mktmpdir do |one|
      Dir.mktmpdir do |two|
        first, second = home_command(one), home_command(two)
        moved(first, second, before_move)
        yield first, second
      ensure
        [first, second].each { |kernel| kernel&.release if kernel.respond_to?(:release) }
      end
    end
  end
end
