# frozen_string_literal: true

module StaleWords
  INTENT_ID = /\bintents? \d+/i
  DATE = /\b20\d\d-\d\d-\d\d\b/
  MONTHS = %w[January February March April May June July August September October November December].freeze
  OLD_LAYOUT = /savepoint\.md|(?<!\w)savepoints(?!\w)|local\.db|routine run|references\.db/
  REMOVED_STORAGE = /work_log_pending|write_id|drain_log|SchemaHome|SchemaStore|no ATTACH|--system\b/
  LONG_DATE = /\b(?:#{MONTHS.join("|")}) \d{1,2}, 20\d\d\b/
  OLD_LAYOUT_READERS = %w[
    lib/plastic/doctor/core.rb
    lib/plastic/graph/backup/integrity.rb
    lib/plastic/graph/database/local.rb
    lib/plastic/graph/knowledge/legacy/savepoint_log.rb
    lib/plastic/graph/knowledge/reader/intent_file.rb
    lib/plastic/graph/knowledge/reader/log_file.rb
    lib/plastic/graph/knowledge/store_path.rb
    lib/plastic/graph/knowledge/sync/old_savepoints.rb
    lib/plastic/graph/migration/home_migration.rb
    lib/plastic/graph/migration/store_migration.rb
    lib/plastic/graph/rows/savepoint.rb
    lib/plastic/graph/schema/migrations/store_from_beta_2.sql
    lib/plastic/graph/work/node_result.rb
    lib/plastic/workflows/sync_steps.rb
    tools/store_proof.rb
    docs/reference/commands/sync-down/README.md
  ].freeze
  STORAGE_WORDS = Regexp.union(OLD_LAYOUT, REMOVED_STORAGE)

  def self.holding(root, paths, pattern = STORAGE_WORDS) = paths.select { |path| File.read(File.join(root, path)).scrub.match?(pattern) }
end
