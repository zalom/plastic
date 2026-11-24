# frozen_string_literal: true

module Plastic
  module Graph
    # The answer of a migration for a database that records versions this code does not know: it was written by newer
    # code, so the run leaves it as it is and names the versions.
    RecordsNewer = Data.define(:versions)
  end
end
