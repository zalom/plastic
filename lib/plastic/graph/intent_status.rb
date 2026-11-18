# frozen_string_literal: true

module Plastic
  module Graph
    # The six states an intent can be in. The schema checks a row against them and the knowledge package groups them.
    module IntentStatus
      ALL = %w[open in_progress parked future done abandoned].freeze
    end
  end
end
