# frozen_string_literal: true

module Plastic
  module Installations
    # The text Plastic installs into ~/.codex/AGENTS.md between its markers:
    # a short pointer to ~/.plastic/PLASTIC.md, never a copy of it, so it
    # cannot drift from it.
    module CodexInstructions
      BODY = <<~MD
        Plastic is installed for this agent. Plastic is intent-driven state management: work runs
        in one of three modes, direct, thinking, or auto (an agent team drives the delivery with
        `plastic status` and `plastic next`). `plastic intent start ID` starts an intent for guided
        work, `plastic intent auto ID` starts it for agent delivery, and `plastic roadmap auto SLUG`
        starts a roadmap's next item. Do not jump straight to code.

        Standing rules:
        - The command line is ~/.plastic/PLASTIC.md. Read it and follow it exactly. The
          conventions are chapters `plastic help TOPIC` prints on demand. Both are
          generated and overwritten on Plastic updates, so never edit them.
        - Operational procedures are the `plastic` command line itself, run directly.
        - Intents, specs, plans, checklists, and outcomes live under ~/.plastic/, never in
          the project tree.

        This section is managed by the Plastic installer. It is replaced on update and removed
        on uninstall. Do not edit anything between the BEGIN and END markers.
      MD
    end
  end
end
