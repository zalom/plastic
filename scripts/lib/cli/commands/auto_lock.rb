# frozen_string_literal: true

require "json"
require_relative "../command"
require_relative "../legacy"

# `plastic auto lock` - inspects, repairs, or releases an intent's delivery
# lock (`plastic-lock status|fix|release --intent-dir DIR`, run through
# Legacy). The verb comes first, then the id, since the verb is what the
# table's two-token match consumes as part of the command name.
#
# `status` and `fix` speak JSON, so this command renders them as a screen and
# leaves the document to `--json`. `release` already reports in prose. A lock
# another session owns exits 3, which travels as a refusal.
module Plastic
  class CLI
    module Commands
      class AutoLock < Command
        USAGE_LINE = "plastic auto lock status|fix|release ID [--json]"

        VERBS = %w[status fix release].freeze
        AFTER = {"status" => "none", "fix" => "plastic auto brief ID",
                 "release" => "plastic session summary"}.freeze
        BECAUSE = {"status" => "inspection is complete; a held lock does not authorize repair",
                   "fix" => "a repaired lock is ready for the preamble again",
                   "release" => "the summary is what a freed lock leads to"}.freeze

        def initialize(argv, runner: nil, **streams)
          super(argv, **streams)
          @runner = runner
        end

        def call
          raise Usage, "VERB must be one of #{VERBS.join(", ")}" unless VERBS.include?(verb)

          case verb
          when "status" then screen(report("status"))
          when "fix" then options[:json] ? run_verb : fix_screen(report("fix"))
          else run_verb
          end
          @output.next_step(AFTER.fetch(verb).sub("ID", id.to_s), because: BECAUSE.fetch(verb))
        end

        private

        def run_verb
          status = legacy.run("plastic-lock", verb, "--intent-dir", intent_dir)
          raise Failure, "plastic-lock exited #{status}" unless status.zero?
        end

        def report(name)
          text, status = legacy.capture("plastic-lock", name, "--intent-dir", intent_dir)
          raise Failure, "plastic-lock exited #{status}" unless status.zero?

          JSON.parse(text)
        rescue JSON::ParserError
          raise Failure, "plastic-lock did not print a report"
        end

        def screen(report)
          @output.row("intent", File.basename(report["intent_dir"].to_s))
          @output.row("lock", lock_line(report))
          @output.row("worktree", worktree_line(report["worktree"]))
          @output.row("delivering", report["delivering"] ? "yes" : "no")
          @output.row("claims", Array(report["claims"]).map(&:to_s))
        end

        def fix_screen(report)
          lock = report["lock"] || {}
          @output.row("lock", "#{report["status"]} by #{lock["owner_session"] || report["session"]}, " \
                              "#{lock["run_mode"]} mode")
          @output.row("actions", Array(report["actions"]).map(&:to_s))
        end

        def lock_line(report)
          lock = report["lock"]
          return "corrupt, plastic auto lock fix #{id} rewrites it" if report["lock_corrupt"]
          return "none" if lock.nil?

          holder = lock.is_a?(Hash) ? (lock["owner_session"] || lock["session"]) : lock
          "held by #{holder}#{", stale" unless report["lock_fresh"]}"
        end

        def worktree_line(worktree)
          return "none" unless worktree.is_a?(Hash) && worktree["provisioned"]

          [worktree["code"], worktree["code_branch"]].compact.join("  on  ")
        end

        def verb
          arguments[0]
        end

        def id
          arguments[1]
        end

        def intent_dir
          dir = scope.intent_dir(id)
          raise Failure, "no intent #{id.inspect} in #{scope.slug}; plastic status lists the ones that exist" unless dir

          dir
        end

        def legacy
          @legacy ||= Legacy.new(env: @env, runner: @runner, output: @output, json: options[:json])
        end
      end
    end
  end
end
