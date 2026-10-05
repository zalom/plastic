# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/backup"

class WorkflowBackupTest < Plastic::TestCase
  # VACUUM INTO never runs inside the test's rolled-back transaction, so the
  # backup runs against a separate home that commits as a real process would.
  def in_fresh_home
    Dir.mktmpdir do |dir|
      graphs = Plastic::Graph.open(home: File.join(dir, ".plastic"), store: "global")
      graphs.work.write_intent(title: "Alpha")
      yield graphs
    end
  end

  def test_a_backup_writes_its_row_and_names_the_archive
    in_fresh_home do |graphs|
      outcome, context = run_workflow(Plastic::Workflows::Backup, graphs:)
      backup = sole(graphs.retrieval.backups)

      assert_equal :done, outcome
      assert_equal ["backup: #{backup.name}, #{backup.files} databases, #{backup.bytes} bytes"], context.printed
    end
  end

  def test_the_archive_the_row_names_is_on_disk_unchanged
    in_fresh_home do |graphs|
      run_workflow(Plastic::Workflows::Backup, graphs:)

      assert_nil graphs.retrieval.backup_flag(sole(graphs.retrieval.backups))
    end
  end
end
