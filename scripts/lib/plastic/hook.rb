# frozen_string_literal: true

require "json"
require_relative "cli/command"

module Plastic
  # A tool the harness calls on an event. Plastic has two: the session
  # start, and the end of every turn. Hooks keep the harness's contract,
  # which differs from a tool's:
  #
  #   stdout  plain text; Claude Code adds it to the agent's context on the
  #           session start event, and shows it nowhere on the stop event
  #   exit    always 0; a broken hook must never break the session
  #   stderr  a diagnostic line, shown only in the harness's debug log
  #
  # So a hook is not a Routine: it prints no next: line, has no routine run, and
  # rescues every error. A hook never stops the agent.
  class Hook < CLI::Command
    def self.call(argv, environment: CLI::Command::Environment.current, **rest)
      new(argv, environment:, **rest).answer
    rescue => error
      environment.err.puts "plastic hook: #{error.class}: #{error.message}"
      CLI::Command::OK
    end

    # Prints the reply to the event, if there is one.
    def answer
      reply = respond(event)
      environment.out.puts reply if reply
      CLI::Command::OK
    end

    # The event JSON the harness writes on stdin, with symbol keys. An event
    # that is not a JSON object, such as `[]` or bad JSON, reads as empty.
    def event
      text = environment.input.read.to_s
      return {} if text.strip.empty?

      parsed = JSON.parse(text, symbolize_names: true)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    # The session the event names, else the environment's; nil when neither
    # names one. A hook with no session id writes no row.
    def session_id(event) = event[:session_id] || session

    # Returns the text to print, or nil to print nothing.
    def respond(_event)
      raise NoMethodError, "#{self.class} must define respond"
    end
  end
end
