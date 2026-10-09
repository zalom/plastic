# frozen_string_literal: true

module Plastic
  class TestCase
    # An intent at each point of the ruled lifecycle, driven through the command line.
    module LifecycleHelper
      KEY = "works"
      CRITERION = "It works"
      EARLY = "2026-10-05T10:00:00+02:00"
      MIDDLE = "2026-10-05T11:00:00+02:00"
      LATE = "2026-10-05T12:00:00+02:00"
      MERGE_RECORDS = "- Merged: plastic/1 into alpha at abc123\n- Architecture map: enola at abc123\n"
      PULL_REQUEST = "- Pull request: https://example.test/pull/1\n"
      APPROVED = "- Approved: the owner on 2026-10-05\n"

      def cli(*args, session: "delivery") = plastic(*args, table: Plastic::CLI::TABLE, env: { "PLASTIC_SESSION" => session })

      def keyed_spec(keys = { KEY => CRITERION })
        "# Spec\n\n## Done criteria\n#{keys.map { |key, text| "- [ ] [#{key}] #{text}\n" }.join}"
      end

      def specified(keys = { KEY => CRITERION }, records: MERGE_RECORDS + PULL_REQUEST + APPROVED)
        intent = open_intent
        write("#{intent.dir}/spec.md", keyed_spec(keys))
        write("#{intent.dir}/outcome.md", "# Outcome\n\nDelivered and verified.\n\n## Verification\n#{records}") if records
        cli("sync", "up")
        intent
      end

      def delivered_nodes(keys = { KEY => CRITERION })
        cli("intent", "approve", "1")
        cli("auto", "1")
        keys.each_key.with_index(1) do |key, number|
          cli("node", "add", "1", "Deliver #{key}", "--criterion", key)
          cli("node", "claim", "1", "n#{number}")
          cli("node", "done", "1", "n#{number}", "Acceptance passes for #{key}")
        end
      end

      def set_node_times(at)
        store_graphs.databases.fetch(:work).transaction { |batch| batch.add("UPDATE nodes SET updated_at = :at", at:) }
      end

      def put_verdict(round, verdict, at, findings: "Checked against the spec")
        store_graphs.databases.fetch(:work).transaction do |batch|
          batch.add("INSERT INTO verdicts(intent_id, round, origin_id, verdict, findings, at, session_id) VALUES (:intent_id, :round, :origin, :verdict, :findings, :at, :session)",
            intent_id: "1", round:, origin:, verdict:, findings:, at:, session: "delivery")
        end
      end

      def work_rows(table) = store_graphs.databases.fetch(:work).rows("SELECT * FROM #{table}")

      def accepted_intent(keys = { KEY => CRITERION }, **specified_options)
        intent = specified(keys, **specified_options)
        delivered_nodes(keys)
        set_node_times(EARLY)
        put_verdict(1, "accept", LATE)
        intent
      end

      def review_off = File.write(File.join(@plastic_home, "config.yml"), "review:\n  pull_request: off\n")
    end
  end
end
