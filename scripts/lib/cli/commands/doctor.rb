# frozen_string_literal: true

require "json"
require_relative "installer_verb"

# `plastic doctor` - diagnoses Plastic installation health. The work is still
# scripts/doctor.rb, run through Legacy; each finding prints its own repair.
# The script speaks JSON, so this command renders it as a screen and keeps the
# document itself behind `--json`, the way every other command reads. A report
# that is not `pass` exits non-zero, because findings are what doctor is for.
#
# InstallerVerb keeps the raw argv rather than running the option parser, so
# `--json` is taken off the line here instead of through `options`.
module Plastic
  class CLI
    module Commands
      class Doctor < InstallerVerb
        USAGE_LINE = "plastic doctor [--core] [--store WHICH] [--json]"
        FLAGS = %w[--core --store].freeze

        SCRIPT = "doctor.rb"
        AFTER = "none"
        BECAUSE = "the findings are the whole answer, and each one names its own repair"

        def call
          as_document = !@argv.delete("--json").nil?
          unknown = arguments.grep(/\A-/) - FLAGS
          raise Usage, "#{unknown.first} is not a flag of this command" unless unknown.empty?

          report = parse(legacy.capture(SCRIPT, *arguments).first)
          as_document ? document(report) : screen(report)
          @output.next_step(AFTER, because: BECAUSE)
          flush
          raise Failure, verdict(report) unless report["status"] == "pass"
        end

        def flush
          @output.flush(json: false) unless @document_printed
        end

        private

        def parse(report)
          JSON.parse(report)
        rescue JSON::ParserError
          raise Failure, "#{SCRIPT} did not print a report"
        end

        def document(report)
          @document_printed = true
          @output.document(report)
        end

        def findings(report)
          report["checks"].to_a.reject { |check| check["status"] == "pass" }
        end

        def verdict(report)
          found = findings(report)
          "doctor found #{found.size} #{(found.size == 1) ? "finding" : "findings"}, listed above"
        end

        def screen(report)
          checks = report["checks"].to_a
          found = findings(report)

          @output.row("status", "#{report["status"]}  #{checks.size - found.size} of #{checks.size} checks pass")
          @output.row("version", report["version"])
          @output.row("agent", report["agent"])
          found.each { |finding| finding_rows(finding) }
        end

        def finding_rows(finding)
          name = [finding["category"], finding["name"]].compact.join("/")
          @output.row(finding["status"], "#{name}  #{finding["message"]}")
          @output.row("", "fix: #{finding["fix_hint"]}") if finding["fix_hint"]
        end
      end
    end
  end
end
