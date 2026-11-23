# frozen_string_literal: true

require_relative "../token_usage"
require_relative "jsonl"
require_relative "claude/transcript"
require_relative "claude/claim"

module Plastic
  module Harnesses
    module Records
      # Reads one node run from Claude Code's local transcripts, `projects/*/SESSION.jsonl`. A subagent that ran the claim command
      # inside the run is the worker: its own file, `SESSION/subagents/agent-ID.jsonl`, holds the usage. The reading of one file is
      # in Claude::Transcript. Docs: docs/usage/node-lifecycle.md.
      class Claude
        SUBAGENT_NOTE = "cost not found: Claude Code writes no cost for a subagent, only for the session"

        def initialize(home:)
          @home = home
        end

        # The usage of the run from `from` to `to`, claimed with `claim` (the intent id and node id), by `session`.
        def read(session:, from:, to:, claim:)
          path = Dir.glob(File.join(@home, ".claude", "projects", "*", "#{session}.jsonl")).min
          return TokenUsage.none("no Claude Code transcript for session #{session}") unless path

          found = self.class.subagent(path, session, from..to, claim)
          worker, window = found || [path, from..to]
          name = File.basename(worker, ".jsonl")
          entries = Jsonl.read(worker)
          window = Claim.window(entries, window, claim) if entries && !found
          entries ? Transcript.new(entries, window, no_cost: (SUBAGENT_NOTE if found)).usage(name) : TokenUsage.none("the Claude Code transcript of session #{name} is unreadable", worker_session: name)
        end

        # The cost of each run of the main file of `session`, in order, nil where the transcript cannot tell it. A run is a
        # [window, claim] pair. The file is read
        # once for all the windows. No subagent file is read: Claude Code writes its `cost-state` lines to the main file only.
        def costs(session:, runs:)
          path = Dir.glob(File.join(@home, ".claude", "projects", "*", "#{session}.jsonl")).min
          entries = path && Jsonl.read(path)
          runs.map { |window, claim| entries && Transcript.new(entries, Claim.window(entries, window, claim)).run_cost }
        end

        # [file, window] of the subagent that ran the claim, or nil. The turn that runs the claim is written before the command
        # executes, so before the run's stored start: the window of the worker starts at that turn and ends with the run.
        def self.subagent(path, session, run, claim)
          files = Dir.glob(File.join(File.dirname(path), session, "subagents", "agent-*.jsonl")).sort
          Claim.nearest(files, run, Claim.pattern(claim))
        end
      end
    end
  end
end
