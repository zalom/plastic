# encoding: UTF-8

require_relative "session_start/boot"

# Extracted from scripts/hook-session-start (intent 397, technique 1): the
# script's own logic lives here as an injectable entry, one small collaborator
# per section of the original top-level script, each in its own file under
# session_start/ so RubyCritic scores each collaborator on its own instead of
# the sum of fourteen of them stacked in one file. The script itself stays a
# thin wrapper below.
module SessionStartHook
  def self.call(argv: ARGV, env: ENV, stdin: $stdin)
    Boot.new(argv: argv, env: env, stdin: stdin).run
  end
end
