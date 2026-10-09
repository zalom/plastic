# frozen_string_literal: true

module Plastic
  class TestCase
    # Calls `plastic auto` as session s-1 and reads back what it wrote.
    module AutoHelper
      CLEAR_SPEC = "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- none\n"

      def call(*args, env: {}) = plastic("auto", *args, env: { "PLASTIC_SESSION" => "s-1" }.merge(env), table: Plastic::CLI::TABLE)

      def write_spec(intent, text)
        write("#{intent.dir}/spec.md", text)
        plastic("sync", "up", table: Plastic::CLI::TABLE)
      end

      def approve(intent_id = "1") = plastic("intent", "approve", intent_id, table: Plastic::CLI::TABLE)

      def clear_intent
        intent = open_intent
        write_spec(intent, CLEAR_SPEC)
        approve(intent.intent_id)
        intent
      end

      def register_repo(path = File.join(@home, "repo"))
        File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  global:\n    path: #{path}\n")
        path
      end

      def next_line(result) = result.out.lines(chomp: true).find { |line| line.start_with?("next: ") }

      def lock_rows = store_graphs.databases.fetch(:local).rows("SELECT * FROM locks")

      def expire_lock
        store_graphs.databases.fetch(:local).transaction do |batch|
          batch.add("UPDATE locks SET renewed_at = '2000-01-01T00:00:00Z'")
        end
      end

      def active_intent
        intent = open_intent
        write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")
        store_graphs.work.activate_intent(intent.intent_id)
        intent
      end
    end
  end
end
