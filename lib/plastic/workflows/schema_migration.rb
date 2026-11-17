# frozen_string_literal: true

require_relative "../wiring"
require_relative "../graph"

module Plastic
  module Workflows
    # The step the install, the update and the restore share: bring the
    # databases of the home to the newest layout, and say which store stayed
    # behind because its backup failed.
    module SchemaMigration
      def self.bring_current(context, slug: nil)
        report = Graph::SchemaRunner.new(home: context.scope.plastic_home, now: context.now, only: slug).call
        report.behind_lines.each { |line| context.print(line) }
        import_config(context) unless slug
        report
      end

      def self.import_config(context)
        line = Wiring.store(context.scope.plastic_home, clock: context.clock).print_once
        context.print(line) if line
      end
    end
  end
end
