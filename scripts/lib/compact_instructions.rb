# encoding: UTF-8
# frozen_string_literal: true

require "digest"

# The text Plastic installs into ~/.claude/CLAUDE.md between its two markers. It is one
# import and nothing else: PLASTIC.md is the only instruction text Plastic carries.
# docs/reference/harness-adapters.md, "Instruction sections", describes the markers.
module CompactInstructions
  # The `@` line is a Claude Code import. It names the installed copy under the Plastic
  # home, because a bare `@PLASTIC.md` would resolve against ~/.claude.
  BODY = <<~MD
    Plastic runs from one command, `plastic`. Its instructions are one page, imported here:

    @~/.plastic/PLASTIC.md
  MD

  def self.body_hash
    Digest::SHA256.hexdigest(BODY)[0, 12]
  end
end
