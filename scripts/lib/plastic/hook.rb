# frozen_string_literal: true

require "json"
require_relative "cli/command"
require_relative "graph/missing_store"

module Plastic
  # A tool the harness calls on an event. Plastic has three: the session
  # start, the end of every turn, and the session end. Hooks keep the
  # harness's contract, which differs from a tool's:
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
    rescue Graph::MissingStore
      CLI::Command::OK
    rescue => error
      environment.err.puts "plastic hook: #{error.class}: #{error.message}"
      CLI::Command::OK
    end

    # Prints the reply to the event, if there is one.
    def answer
      return help if argv.intersect?(%w[--help -h])

      reply = respond(event)
      environment.out.puts reply if reply
      CLI::Command::OK
    rescue OptionParser::ParseError => error
      environment.err.puts "plastic: #{error.message}", usage_line
      CLI::Command::OK
    end

    # The event JSON the harness writes on stdin, with symbol keys, read
    # once. An event that is not a JSON object, such as `[]` or bad JSON,
    # reads as empty.
    def event = (@event ||= read_event)

    # The session the event names, else the environment's; nil when neither
    # names one. A hook with no session id writes no row.
    def session_id = event[:session_id] || environment.session

    # Where the session runs: the event's cwd, else the process's directory.
    def directory = event[:cwd] || environment.directory

    # Returns the text to print, or nil to print nothing.
    def respond(_event)
      raise NoMethodError, "#{self.class} must define respond"
    end

    private

    def read_event
      text = environment.input.read.to_s
      text.strip.empty? ? {} : parsed_event(text)
    end

    def parsed_event(text)
      parsed = JSON.parse(text, symbolize_names: true)
      parsed.is_a?(Hash) ? parsed : unreadable
    rescue JSON::ParserError
      unreadable
    end

    def unreadable
      environment.err.puts "plastic hook: the event is not a JSON object; read as empty"
      {}
    end

    # The store comes from the directory the event names, so a hook run from
    # another folder still reads the session's own project.
    def scope
      @scope ||= CLI::Scope.new(env: environment.env, home: environment.home, slug: parsed[:project], directory:)
    end
  end
end
