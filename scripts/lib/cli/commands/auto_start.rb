# frozen_string_literal: true

require "json"
require_relative "intent_command"
require_relative "../../roadmap_graph"

# `plastic auto start` - arms the intent's delivery lock for this session
# (`plastic-lock arm --intent-dir DIR --mode auto`, run through Legacy).
# Given a roadmap slug instead of an id, it arms the roadmap's first ready
# intent in file order and prints the rest of the ready queue (intent 391).
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
      class AutoStart < IntentCommand
        USAGE_LINE = "plastic auto start ID|ROADMAP-SLUG [--allow-inline] [--harness NAME] [--agent NAME] " \
                     "[--model MODEL] [--thread ID] [--json]"

        SCRIPT = "plastic-lock"
        AFTER = "plastic auto brief ID"
        BECAUSE = "the preamble is the live state a taken intent is read from next"
        CREATE_BECAUSE = "Plastic runs no version control command; it creates no worktree itself"
        PROVENANCE = %i[harness agent model thread].freeze
        EMPTY_BECAUSE = "no roadmap entry is queued with every dependency delivered"

        def call
          return start_roadmap if roadmap?
          return super if options[:json]

          arm
        end

        private

        def arm
          text, status = legacy.capture(SCRIPT, *script_arguments)
          raise Failure, "#{SCRIPT} exited #{status}" unless status.zero?

          report = JSON.parse(text)
          screen(report)
          command, reason = next_step_for(report)
          @output.next_step(command, because: reason)
        rescue JSON::ParserError
          raise Failure, "#{SCRIPT} did not print a report"
        end

        def id
          @id || arguments.first
        end

        def roadmap?
          return false if arguments.first.to_s.empty? || scope.intent_dir(arguments.first)

          File.file?(roadmap_path)
        end

        def roadmap_path
          File.join(scope.roadmaps_dir, "#{arguments.first}.md")
        end

        def start_roadmap
          slug = arguments.first
          result = RoadmapGraph.analyze(roadmap_path, index_path: scope.index_path)
          raise Failure, "#{slug} cannot start: #{result[:reason]}; plastic roadmap check #{slug} says more" if result[:reason]
          raise Failure, "#{slug} has a cycle or a dangling id; plastic roadmap check #{slug} names it" if result[:cycle] || result[:dangling].any?

          @output.row("roadmap", slug)
          ready = result[:ready]
          return arm_first(ready) if ready.any?

          blocked = result[:entries].values.find { |entry| entry[:status] == "blocked" }
          raise Refusal, "#{slug} entry #{blocked[:id]} is blocked and needs a decision" if blocked

          @output.row("ready", "none")
          @output.next_step("plastic roadmap show #{slug}", because: EMPTY_BECAUSE)
        end

        def arm_first(ready)
          @id = ready.first
          @output.row("queue", (ready.length > 1) ? ready.drop(1).join(", ") : "none")
          arm
        end

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
