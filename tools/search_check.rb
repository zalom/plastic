# frozen_string_literal: true

# Runs a file of known questions through Plastic's own search class against a store and reports, for each question,
# the rank of the first known answer among the first intents returned. Exact: no model call. The store opens
# read-only, with no migration and no schema prepare, so a run writes nothing.
module SearchCheck
end

require_relative "search_check/usage"
require_relative "search_check/read_only_store"
require_relative "search_check/question"
require_relative "search_check/switches"
require_relative "search_check/arguments"
require_relative "search_check/ranker"
require_relative "search_check/check"
require_relative "search_check/cli"
