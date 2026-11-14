# frozen_string_literal: true

require_relative "../store_folder"

module Plastic
  module Graph
    module Knowledge
      class Sync
        # What a sync settles for one entry, given the resolution and the files sync up cannot read.
        module Settling
          # The action of this entry once the overwrite and the unreadable files are weighed.
          def settle(resolution, unreadable)
            direction = resolution.direction
            return generated_up(unreadable) if direction == :up && generated?
            return :none if unreadable.key?(path)

            resolved(action(direction), resolution)
          end

          # A changed file that is the index or belongs to an intent that has its rows; the files of a folder without rows read after its row is written.
          def readable_in?(rowed)
            return false unless %i[read conflict].include?(action(:up))

            index? || (!generated? && inside_any?(rowed))
          end

          private

          def index? = path == StoreFolder::INDEX

          def inside_any?(dirs) = dirs.any? { |dir| path.start_with?("#{dir}/") }

          # A generated file a person changed: the index is read when it can be, else printed again from the rows.
          def generated_up(unreadable)
            return :none unless hand_edited? && rows_sha

            (Entry.reprinted?(path) || unreadable.key?(path)) ? :print : :read
          end

          def resolved(action, resolution)
            return resolution.side if action == :conflict && resolution.overwrites?(path)

            named_print?(resolution) ? :print : action
          end

          # An overwrite that names this path prints it from its rows when the file differs from them.
          def named_print?(resolution) = resolution.direction == :down && resolution.names?(path) && rows_sha && !level?
        end
      end
    end
  end
end
