# frozen_string_literal: true

module Plastic
  class TestCase
    # Calls `plastic intent auto` and `plastic intent start` as session s-1 and reads back what they wrote.
    module AutoHelper
      CLEAR_SPEC = "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- none\n"

      def call(*args, env: {}) = as_session("intent", "auto", *args, env:)

      def start(*args, env: {}) = as_session("intent", "start", *args, env:)

      def as_session(*words, env:) = plastic(*words, env: { "PLASTIC_SESSION" => "s-1" }.merge(env), table: Plastic::CLI::TABLE)

      def write_spec(intent, text)
        write("#{intent.dir}/spec.md", text)
        plastic("sync", "up", table: Plastic::CLI::TABLE)
      end

      def approve(intent_id = "1") = plastic("intent", "approve", intent_id, table: Plastic::CLI::TABLE)

      def clear_intent(**fields)
        intent = open_intent(**fields)
        write_spec(intent, CLEAR_SPEC)
        approve(intent.intent_id)
        intent
      end

      def register_repo(path = File.join(@home, "repo"))
        File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  global:\n    path: #{path}\n")
        path
      end

      def next_line(result) = result.out.lines(chomp: true).find { |line| line.start_with?("next: ") }

      def claim_rows = store_graphs.databases.fetch(:store).rows("SELECT * FROM nodes WHERE state = 'claimed'")

      def status_of(intent_id) = retrieval.intent(intent_id).status

      def set_status(intent_id, status)
        store_graphs.databases.fetch(:store).transaction do |batch|
          batch.write(:intents, "UPDATE intents SET status = :status WHERE intent_id = :intent_id", intent_id:, status:)
        end
      end

      def active_intent
        intent = open_intent
        write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")
        approve(intent.intent_id)
        store_graphs.work.activate_intent(intent.intent_id)
        intent
      end
    end
  end
end
