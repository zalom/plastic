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
          entries ? Transcript.new(entries, window, subagent: !found.nil?).usage(name) : TokenUsage.none("the Claude Code transcript of session #{name} is unreadable", worker_session: name)
        end

        # The cost of each window of the main file of `session`, in order, nil where the transcript cannot tell it. The file is read
        # once for all the windows. No subagent file is read: Claude Code writes its `cost-state` lines to the main file only.
        def costs(session:, windows:)
          path = Dir.glob(File.join(@home, ".claude", "projects", "*", "#{session}.jsonl")).min
          entries = path && Jsonl.read(path)
          windows.map { |window| entries && Transcript.new(entries, window).run_cost }
        end

        # [file, window] of the subagent that ran the claim, or nil. The turn that runs the claim is written before the command
        # executes, so before the run's stored start: the window of the worker starts at that turn and ends with the run.
        def self.subagent(path, session, run, claim)
          files = Dir.glob(File.join(File.dirname(path), session, "subagents", "agent-*.jsonl")).sort
          Claim.nearest(files, run, /node claim #{Regexp.escape(claim)}(\s|\z)/)
        end
      end
    end
  end
end
