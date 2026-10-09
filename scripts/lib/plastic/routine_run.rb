# frozen_string_literal: true

require "json"

module Plastic
  # One call of one tool on one subject, kept as a row of the work graph.
  #
  # A routine run records the facts, the workflows that finished, and where the call
  # stopped (`at`), so a call after a hand-off keeps every fact the first
  # call found. While the routine run is open, the next call of
  # the same tool on the same subject loads those facts and starts at the
  # entry again: done checks skip the finished work, and code before an agent
  # handoff sees what the agent changed.
  #
  #   status   running    the process is inside the chain, or died there
  #            handed_off the agent has steps; the next call checks them
  #            failed     a step broke; the next call retries that workflow
  #            refused    the owner holds a step; the next call asks again
  #            finished   the chain ended; the next call starts a new routine run
  #
  # A tool that writes keeps its routine run as a row, so a resumed call
  # sees the same memory the first one left. A read and a dry run keep none.
  # The fields are the columns of the routine_runs table, in order. A routine
  # run never changes; `advance` and `close` return the next one.
  RoutineRun = Data.define(:tool, :subject, :at, :finished, :status, :facts, :next_command, :because, :exit_code,
    :started_at, :updated_at)

  # A routine run's status, its fields, and the next routine run.
  class RoutineRun
    OPEN = %w[running handed_off failed refused].freeze

    FIELDS = members.freeze

    # The run in one phrase: the tool, its status, when, and the next command it printed.
    def summary = [tool, status, updated_at].join(" ") + Array(next_command).map { |command| ", next: #{command}" }.join

    def self.fresh(tool, subject)
      now = Plastic.now
      new(tool:, subject:, at: nil, finished: [], status: "running", facts: {},
        next_command: nil, because: nil, exit_code: nil, started_at: now, updated_at: now)
    end

    def self.from_h(hash)
      values = hash.transform_keys(&:to_sym)
      new(**values.merge(facts: values[:facts].transform_keys(&:to_sym), at: values[:at]&.to_sym,
        finished: values[:finished].map(&:to_sym)))
    end

    # A row of the routine_runs table: facts and finished are JSON text, the
    # subject is the one the caller asked for, nil included, and the session
    # that wrote the row is call memory, not a field of the routine run.
    def self.from_row(row, subject)
      from_h(row.except("store", "session_id").merge("subject" => subject, "facts" => JSON.parse(row.fetch("facts")),
        "finished" => JSON.parse(row.fetch("finished"))))
    end

    def initialize(**values)
      missing = FIELDS - values.keys
      raise ArgumentError, "a routine run needs #{missing.join(", ")}" if missing.any?

      super
    end

    def open? = OPEN.include?(status)

    def key = [tool, subject].compact.join(" ")

    # A workflow finished and the chain moves on.
    def advance(from, to) = with(finished: finished | [from], at: to, status: "running", updated_at: Plastic.now)

    # The call ends. `value` is Finished, HandedOff, Failed or Refused, and it
    # names the status and the lines the routine run keeps.
    def close(value, facts) = with(facts:, updated_at: Plastic.now, **value.record)
  end
end
