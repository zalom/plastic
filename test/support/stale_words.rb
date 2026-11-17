# frozen_string_literal: true

module StaleWords
  INTENT_ID = /\bintents? \d+/i
  DATE = /\b20\d\d-\d\d-\d\d\b/
  MONTHS = %w[January February March April May June July August September October November December].freeze
  OLD_LAYOUT = /savepoint\.md|(?<!\w)savepoints(?!\w)|local\.db|routine run|references\.db/
  REMOVED_STORAGE = /work_log_pending|write_id|drain_log|SchemaHome|SchemaStore|no ATTACH|--system\b/
  LONG_DATE = /\b(?:#{MONTHS.join("|")}) \d{1,2}, 20\d\d\b/
end
