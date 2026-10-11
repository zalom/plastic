# frozen_string_literal: true

module StaleWords
  INTENT_ID = /\bintents? \d+/i
  DATE = /\b20\d\d-\d\d-\d\d\b/
  MONTHS = %w[January February March April May June July August September October November December].freeze
  LONG_DATE = /\b(?:#{MONTHS.join("|")}) \d{1,2}, 20\d\d\b/
end
