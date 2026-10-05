# frozen_string_literal: true

require "fileutils"
require_relative "../backup"

module Plastic
  module Graph
    module Knowledge
      class Backup
        # Puts one backup file in place of a store database by rename. The old
        # file waits beside it until every replacement of the restore is done,
        # so a failure can put each one back.
        class Replacement
          SIDECARS = %w[-journal -wal -shm].freeze

          # Applies every replacement, or undoes the ones that were applied.
          def self.apply_all(replacements)
            applied = []
            apply_each(replacements, applied).each(&:commit)
          rescue
            applied.reverse_each(&:undo)
            raise
          end

          def self.apply_each(replacements, applied)
            replacements.each_with_object(applied) { |replacement, list| list << replacement.apply }
          end

          def initialize(source, target)
            @source = source
            @target = target
            @moved = false
            @placed = false
          end

          def apply
            prepare
            place
            self
          rescue
            undo
            raise
          end

          def commit = FileUtils.rm_f(aside)

          def undo
            FileUtils.rm_f(copy)
            return File.rename(aside, @target) if @moved

            FileUtils.rm_f(@target) if @placed
          end

          private

          def prepare
            SIDECARS.each { |suffix| FileUtils.rm_f("#{@target}#{suffix}") }
            FileUtils.cp(@source, copy)
          end

          def place
            move_aside
            File.rename(copy, @target)
            @placed = true
          end

          def copy = "#{@target}.restoring"

          def aside = "#{@target}.old"

          def move_aside
            return unless File.exist?(@target)

            File.rename(@target, aside)
            @moved = true
          end
        end
      end
    end
  end
end
