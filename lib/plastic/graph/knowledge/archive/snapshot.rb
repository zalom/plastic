# frozen_string_literal: true

require_relative "../archive"
require "tmpdir"
require_relative "layout"
require_relative "entries"
require_relative "../../sql"
require_relative "../../file_system"

module Plastic
  module Graph
    module Knowledge
      class Archive
        # Durable directory entries, separate from live documents and kept-file rows.
        class Snapshot
          def initialize(database, intent_id, origin_id, files: FileSystem.new)
            @database = database
            @files = files
            @intent_id = intent_id
            @origin_id = origin_id
          end

          def capture(batch, entries)
            batch.remove(:archive_entries, intent_id: @intent_id)
            entries.each { |entry| batch.put(:archive_entries, Entries.stored(entry, @intent_id)) }
          end

          def entries
            @database.rows("SELECT path, kind, mode, mtime, data FROM archive_entries WHERE intent_id = :id AND origin_id = :origin",
              id: @intent_id, origin: @origin_id).map { |row| row.transform_keys(&:to_sym) }.sort_by { |row| row[:path] }
          end

          def remove(root)
            saved = checked_entries
            current = Tree.read(root)
            changed = Entries.changed(current, saved)
            raise Tree::Error, "#{root}/#{changed[:path]} changed after archive capture; preserved" if changed

            @files.remove_entry(root) unless current.empty?
          end

          def restore(root)
            saved = checked_entries
            current = Tree.read(root)
            unless current.empty?
              raise Tree::Error, "#{root} differs from the archive; move it aside before restoring" unless Entries.same?(current, saved)

              return
            end
            publish(root, saved)
          end

          private

          def checked_entries
            entries.tap do |rows|
              raise Tree::Error, "intent #{@intent_id} has no archive snapshot" if rows.empty?

              Layout.validate(rows)
            end
          end

          def publish(root, saved)
            stage = Dir.mktmpdir(".plastic-archive-", File.dirname(root))
            begin
              Entries.build(stage, saved)
              raise Tree::Error, "archive snapshot verification failed" unless Entries.same?(Tree.read(stage), saved)
              raise Tree::Error, "#{root} appeared during restoration; preserved" if File.exist?(root) || File.symlink?(root)

              @files.rename(stage, root)
            ensure
              FileUtils.rm_rf(stage)
            end
          end
        end
      end
    end
  end
end
