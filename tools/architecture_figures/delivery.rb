# frozen_string_literal: true

require_relative "delivery/phases"
require_relative "delivery/table"

module ArchitectureFigures
  # The two delivery figures. See docs/contributing/ARCHITECTURE.md.
  module Delivery
    def self.diagrams = Phases.diagrams + Table.diagrams

    def self.files = Diagram.merge(diagrams)

    def self.names = Phases.names + Table.names
  end
end
