# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "open3"

# HookReplay (intent 331a, T1) - the hermetic port of resources/probes/
# replay_hook.rb. The probe read HOOK from ~/.claude/hooks/plastic-message-
# display and buffered under a directory beside itself; neither is safe
# inside the suite, which must never touch a real install or the ambient
# session's own buffer state. Both are constructor arguments here instead:
# hook_path names the launcher to run (the repo's own hooks/message-display
# in tests) and tmp_root is a caller-owned Dir.mktmpdir, exactly like every
# other spawning test in this file isolates PLASTIC_TMP.
module HookReplay
  module_function

  # Streams `text` through `hook_path` in fixed-size chunks, the way Claude
  # Code streams an assistant reply, and returns every chunk's raw stdout so
  # a caller can inspect blanking/passthrough per index as well as the final
  # splice. `session_id`/`message_id` default to fixed values since nothing
  # about a replay depends on the ambient session at all.
  def replay(hook_path:, tmp_root:, text:, chunk: 40, session_id: "s-replay", message_id: "replay")
    chunks = text.scan(/.{1,#{chunk}}/m)
    chunks = [""] if chunks.empty?
    chunks.each_with_index.map do |delta, i|
      payload = {
        "session_id" => session_id, "message_id" => message_id, "index" => i,
        "final" => i == chunks.length - 1, "delta" => delta, "cwd" => tmp_root,
        "hook_event_name" => "MessageDisplay",
      }
      out, err, status = Open3.capture3({ "PLASTIC_TMP" => tmp_root }, hook_path,
                                         stdin_data: JSON.generate(payload))
      { index: i, exitstatus: status.exitstatus, stdout: out, stderr: err, final: payload["final"] }
    end
  end

  # The final chunk's parsed displayContent, or nil when it emitted nothing
  # (no envelope at all: the message never engaged).
  def final_display_content(outs)
    final = outs.last
    return nil if final[:stdout].to_s.empty?

    JSON.parse(final[:stdout]).dig("hookSpecificOutput", "displayContent")
  rescue JSON::ParserError
    nil
  end
end
