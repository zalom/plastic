# encoding: UTF-8

require "json"

module SessionStartHook
  # Reads the stdin payload once: the session id it carries, and whether this
  # boot runs inside a spawned agent (intent 355 D9, n7/n8 B6). Any exception
  # here still boots the banner, never nothing.
  module StdinPayload
    def self.read(stdin)
      payload = parse(stdin)
      session_id = payload.is_a?(Hash) ? payload["session_id"].to_s : ""
      [session_id, subagent?(payload)]
    end

    def self.parse(stdin)
      return nil if stdin.tty?

      raw = stdin.read
      (raw && !raw.strip.empty?) ? JSON.parse(raw) : nil
    rescue
      nil
    end

    def self.subagent?(payload)
      payload.is_a?(Hash) && !!payload["agent_id"]
    rescue
      false
    end
  end
end
