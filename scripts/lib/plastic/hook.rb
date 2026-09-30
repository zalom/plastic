# frozen_string_literal: true

require "json"
require_relative "cli/command"

module Plastic
  # A tool the harness calls on an event. Plastic has two: the session
  # start, and the end of every turn. Hooks keep the harness's contract,
  # which differs from a tool's:
  #
  #   stdout  one JSON object the harness reads, or nothing
  #   exit    always 0; a broken hook must never break the session
  #   stderr  a diagnostic line, shown only in the harness's debug log
  #
  # So a hook is not a Routine: it prints no next: line, has no routine run, and
  # rescues every error. A hook that refused would print a refusal
  # where the harness expects JSON. A hook never stops the agent.
  class Hook < CLI::Command
    # The event name the harness sends, and the reply shape it accepts.
    # These are Claude Code's; another harness gets its own Reply.
    module Reply
      def self.context(event, text)
        {hookSpecificOutput: {hookEventName: event, additionalContext: text}}
      end
    end

    def self.call(argv, out:, err:, **rest)
      hook = new(argv, out:, err:, **rest)
      reply = hook.respond(hook.event)
      out.puts JSON.generate(reply) if reply
      CLI::Command::OK
    rescue => e
      err.puts "plastic hook: #{e.class}: #{e.message}"
      CLI::Command::OK
    end

    # The event JSON the harness writes on stdin, with symbol keys.
    def event
      text = @environment.input.read.to_s
      text.strip.empty? ? {} : JSON.parse(text, symbolize_names: true)
    end

    # Returns a Hash to print, or nil to print nothing.
    def respond(_event)
      raise NoMethodError, "#{self.class} must define respond"
    end
  end
end
