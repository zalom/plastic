# frozen_string_literal: true

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
  # A tool that writes nothing keeps no routine run row: its routine run lives in memory.
  class RoutineRun
    OPEN = %w[running handed_off failed refused].freeze

    # The columns of the routine_runs table, in order.
    FIELDS = %i[tool subject at finished status facts next_command because exit_code
      started_at updated_at].freeze

    attr_reader(*FIELDS)

    def self.fresh(tool, subject)
      now = Plastic.now
      new(tool:, subject:, at: nil, finished: [], status: "running", facts: {},
        next_command: nil, because: nil, exit_code: nil, started_at: now, updated_at: now)
    end

    def self.from_h(hash)
      values = hash.transform_keys(&:to_sym)
      values[:facts] = values[:facts].transform_keys(&:to_sym)
      values[:at] = values[:at]&.to_sym
      values[:finished] = values[:finished].map(&:to_sym)
      new(**values)
    end

    def initialize(**values)
      missing = FIELDS - values.keys
      raise ArgumentError, "a routine run needs #{missing.join(", ")}" if missing.any?

      FIELDS.each { |field| instance_variable_set(:"@#{field}", values.fetch(field)) }
    end

    def open? = OPEN.include?(status)

    def key = [tool, subject].compact.join(" ")

    # A workflow finished and the chain moves on.
    def advance(from, to)
      @finished |= [from]
      @at = to
      touch("running")
    end

    # The call ends. `value` is Finished, HandedOff, Failed or Refused, and
    # the status is its snake name.
    def close(value, facts)
      @facts = facts
      @next_command = value.respond_to?(:next_command) ? value.next_command : nil
      @because = value.respond_to?(:because) ? value.because : value.message
      @exit_code = value.exit_code
      touch(value.class.name.split("::").last.gsub(/(?<=[a-z])(?=[A-Z])/, "_").downcase)
    end

    def to_h = FIELDS.to_h { |field| [field, public_send(field)] }

    private

    def touch(status)
      @status = status
      @updated_at = Plastic.now
      self
    end
  end
end
