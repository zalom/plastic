# encoding: UTF-8
# frozen_string_literal: true

require "digest"

# The compaction thresholds and the text Plastic installs into ~/.claude/CLAUDE.md
# (intent 312; intent 296 D35 and D38).
#
# One home for the body, because two halves need it: installer_core.rb installs the
# marked section, doctor_core.rb verifies the installed one is current. Same reason
# hook_registry.rb is a shared lib rather than a literal duplicated on both sides.
#
# The thresholds are absolute token counts, not percentages. From
# research--context-thresholds.md: models are reliable only to roughly 50 to 65 percent
# of advertised context, and the mechanisms behind that (lost-in-the-middle, attention
# dilution, distractor interference) are architectural, so a bigger window does not
# repeal them. A percentage that is right at 200k, carried to 1M, would let five times
# as many raw tokens accumulate before it fired.
#
# Library only: no CLI, no ENV, no I/O.
module CompactInstructions
  # 35 and 50 percent of a 1M window.
  OFFER_TOKENS = 350_000
  INSIST_TOKENS = 500_000

  # Static on purpose. A body rendered from the user's config would change its hash
  # every time they edited config.yml, and doctor would then report a correct install
  # as stale, so the block states the shipped numbers and names the two keys as the
  # override instead. It names the hand-off in words and never by path, so it reads
  # correctly whether or not the hand-off writer is installed.
  BODY = <<~MD.freeze
    Plastic watches this session's context. When the harness reports how much of the
    window is used:

    - At 350,000 tokens, offer to compact. Say that the hand-off in today's day ledger
      is written and current, and take no for an answer: a task that is nearly done
      does not need the interruption.
    - At 500,000 tokens, insist. Take no new work, write the hand-off in today's day
      ledger, and compact before continuing.
    - After a compaction, say continue. The day summary at boot and the hand-off carry
      the state; do not rebuild it by re-reading files.

    Both numbers are absolute token counts for a 1M window. `context_offer_tokens` and
    `context_insist_tokens` in `~/.plastic/config.yml` override them.

    This section is managed by the Plastic installer. It is replaced on update and
    removed on uninstall. Do not edit anything between the BEGIN and END markers.
  MD

  # The freshness hash the installer stamps into the BEGIN marker, so doctor can tell
  # a current block from one an older version left behind. Same arithmetic as
  # InstallerCore#marked_section, pinned equal by compact_instructions_test.
  def self.body_hash
    Digest::SHA256.hexdigest(BODY)[0, 12]
  end
end
