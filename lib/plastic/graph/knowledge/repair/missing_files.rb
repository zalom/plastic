# frozen_string_literal: true

require_relative "../../../layout"
require_relative "../intent"
require_relative "../sync_selection"

module Plastic
  module Graph
    module Knowledge
      module Repair
        # The files the layout requires of a done or abandoned intent in its state that its folder lacks. A closed intent is
        # never written again, so each missing file is listed only and never invented. The required files come from
        # Plastic::Layout.required_in. `states` maps the id of each closed intent to its status, `dirs` names the folders
        # the call reads, and a path in `arriving`, the target of a move the repair makes, counts as there. It writes nothing.
        class MissingFiles
          WHY = "a closed intent is not written again, so the repair lists it only"

          # The missing files of one intent folder, with the state that requires them.
          Missing = Data.define(:dir, :state, :names) do
            def lines = names.map { |name| "missing #{dir}/#{name}: the layout requires it of #{article} #{state} intent; #{WHY}" }

            # The row text the doctor prints for the folder.
            def text = "#{state}, and lacks #{names.join(", ")}; #{WHY}"

            private

            def article = state.match?(/\A[aeiou]/) ? "an" : "a"
          end

          FINISHED = Intent::GROUPS.fetch("finished")

          # The status of each done or abandoned intent among `intents`, by its id.
          def self.states(intents) = closed(intents.map { |intent| [intent.intent_id, intent.status] })

          # The pairs of an id and a status whose status is done or abandoned, as a map from the id to the status.
          def self.closed(pairs) = pairs.select { |_, status| FINISHED.include?(status) }.to_h

          def initialize(folder, states, dirs:, arriving: [])
            @folder = folder
            @states = states
            @dirs = dirs
            @arriving = arriving.to_set
          end

          def to_a = @dirs.filter_map { |dir| missing(dir) }

          def lines = to_a.flat_map(&:lines)

          private

          def missing(dir)
            state = @states[SyncSelection.intent_of(dir)]
            return unless state

            names = Layout.required_in(state).map(&:name).reject { |name| there?("#{dir}/#{name}") }
            Missing.new(dir:, state:, names:) unless names.empty?
          end

          def there?(path) = @folder.exist?(path) || @arriving.include?(path)
        end
      end
    end
  end
end
