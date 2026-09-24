# frozen_string_literal: true

require "json"
require_relative "intent_command"

# `plastic auto take` - arms the intent's delivery lock for this session
# (`plastic-lock arm --intent-dir DIR --mode auto`, run through Legacy).
# The lock records who took it: --harness, --agent, --model and --thread pass
# through, and a Claude Code session names its harness when none is given.
# plastic-lock answers in JSON, so this command renders it as a screen and
# leaves the document to `--json`. A lock another session owns exits 3.
#
# Plastic creates no worktree itself (intent 390): the screen names the
# expected code worktree path and branch, and the `next:` line is the exact
# `git worktree add` the agent runs to create it -- Plastic never runs it.
module Plastic
  class CLI
    module Commands
      class AutoTake < IntentCommand
        USAGE_LINE = "plastic auto take ID [--allow-inline] [--harness NAME] [--agent NAME] " \
                     "[--model MODEL] [--thread ID] [--json]"

        SCRIPT = "plastic-lock"
        AFTER = "plastic auto brief ID"
        BECAUSE = "the preamble is the live state a taken intent is read from next"
        CREATE_BECAUSE = "Plastic runs no version control command; it creates no worktree itself"
        PROVENANCE = %i[harness agent model thread].freeze

        def call
          return super if options[:json]

          text, status = legacy.capture(SCRIPT, *script_arguments)
          raise Failure, "#{SCRIPT} exited #{status}" unless status.zero?

          report = JSON.parse(text)
          screen(report)
          command, reason = next_step_for(report)
          @output.next_step(command, because: reason)
        rescue JSON::ParserError
          raise Failure, "#{SCRIPT} did not print a report"
        end

        private

        def switches(parser)
          parser.on("--allow-inline") { @options[:allow_inline] = true }
          PROVENANCE.each do |name|
            parser.on("--#{name} VALUE") { |value| @options[name] = value }
          end
        end

        def script_arguments
          args = ["arm", "--intent-dir", intent_dir, "--mode", "auto"]
          provenance.each { |name, value| args.push("--#{name}", value) }
          args << "--allow-inline" if options[:allow_inline]
          args
        end

        def provenance
          given = PROVENANCE.to_h { |name| [name, options[name]] }
          given[:harness] ||= "claude" if @env["CLAUDE_CODE_SESSION_ID"].to_s.strip != ""
          given.compact
        end

        def screen(report)
          worktree = report["worktree"] || {}
          @output.row("intent", File.basename(report["intent_dir"].to_s))
          @output.row("lock", "#{report["status"]} by #{report["session"]}, #{report["run_mode"]} mode")
          @output.row("worktree", worktree_row(worktree))
        end

        def worktree_row(worktree)
          return "none" if worktree["code"].nil?

          "#{worktree["code"]} (#{worktree["provisioned"] ? "present" : "not yet created"})"
        end

        # A store-only project (`code` blank) has no worktree to create, so
        # the next step stays the preamble read. Otherwise it is the exact
        # `git worktree add` that creates the expected workspace: Plastic
        # only prints it, it never runs it.
        def next_step_for(report)
          worktree = report["worktree"] || {}
          code = worktree["code"]
          return after_run if code.nil?

          repo = code.sub(%r{/\.claude/worktrees/[^/]+\z}, "")
          ["git -C #{repo} worktree add #{code} -b #{worktree["code_branch"]}", CREATE_BECAUSE]
        end
      end
    end
  end
end
