# frozen_string_literal: true

require_relative "delivery/phases"
require_relative "delivery/table"

module ArchitectureFigures
  # The two delivery figures. See docs/contributing/ARCHITECTURE.md.
  module Delivery
    def self.files = Phases.files.merge(Table.files)

    def self.names = Phases.names + Table.names
  end
end
