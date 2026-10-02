# frozen_string_literal: true

require "tmpdir"
require_relative "archive_layout"
require_relative "sql"

module Plastic
  module Graph
    # Durable directory entries, separate from live documents and kept-file rows.
    class ArchiveSnapshot
      def initialize(database, intent_id, origin_id)
        @database = database
        @intent_id = intent_id
        @origin_id = origin_id
      end

      def capture(batch, entries)
        batch.remove(:archive_entries, intent_id: @intent_id)
        entries.each do |entry|
          row = entry.merge(intent_id: @intent_id, data: entry[:data] && SQL::Bytes.new(entry[:data]))
          batch.put(:archive_entries, row)
        end
      end

      def entries
        @database.rows("SELECT path, kind, mode, mtime, data FROM archive_entries WHERE intent_id = :id AND origin_id = :origin",
          id: @intent_id, origin: @origin_id).map { |row| row.transform_keys(&:to_sym) }.sort_by { |row| row[:path] }
      end

      def remove(root)
        saved = checked_entries
        current = ArchiveTree.read(root)
        changed = current.find { |entry| !matches?(entry, saved.find { |row| row[:path] == entry[:path] }, metadata: entry[:kind] != "directory") }
        raise ArchiveTree::Error, "#{root}/#{changed[:path]} changed after archive capture; preserved" if changed

        FileUtils.remove_entry(root) unless current.empty?
      end

      def restore(root)
        saved = checked_entries
        current = ArchiveTree.read(root)
        unless current.empty?
          raise ArchiveTree::Error, "#{root} differs from the archive; move it aside before restoring" unless same?(current, saved)

          return
        end
        publish(root, saved)
      end

      private

      def checked_entries
        entries.tap do |rows|
          raise ArchiveTree::Error, "intent #{@intent_id} has no archive snapshot" if rows.empty?

          ArchiveLayout.validate(rows)
        end
      end

      def same?(left, right)
        left.size == right.size && left.all? { |entry| matches?(entry, right.find { |row| row[:path] == entry[:path] }, metadata: true) }
      end

      def matches?(left, right, metadata:)
        return false unless right

        fields = metadata ? %i[path kind mode mtime data] : %i[path kind mode data]
        fields.all? { |key| left[key] == right[key] }
      end

      def publish(root, saved)
        stage = Dir.mktmpdir(".plastic-archive-", File.dirname(root))
        begin
          build(stage, saved)
          raise ArchiveTree::Error, "archive snapshot verification failed" unless same?(ArchiveTree.read(stage), saved)
          raise ArchiveTree::Error, "#{root} appeared during restoration; preserved" if File.exist?(root) || File.symlink?(root)

          File.rename(stage, root)
        ensure
          FileUtils.rm_rf(stage)
        end
      end

      def build(stage, saved)
        saved.sort_by { |row| row[:path].count("/") }.each { |row| write_entry(stage, row) }
        saved.sort_by { |row| -row[:path].split("/").size }.each { |row| metadata(stage, row) }
      end

      def write_entry(stage, row)
        path = safe_path(stage, row[:path])
        case row[:kind]
        when "directory" then FileUtils.mkdir_p(path)
        when "file" then File.binwrite(path, row[:data])
        when "link" then File.symlink(row[:data], path)
        else raise ArchiveTree::Error, "invalid archive entry kind #{row[:kind]}"
        end
      end

      def metadata(stage, row)
        path = safe_path(stage, row[:path])
        time = Time.at(Rational(row[:mtime]))
        if row[:kind] == "link"
          File.lchmod(row[:mode], path) if File.lstat(path).mode & 0o7777 != row[:mode]
        else
          File.chmod(row[:mode], path)
        end
        File.lutime(time, time, path)
      end

      def safe_path(root, relative)
        raise ArchiveTree::Error, "invalid archive path #{relative}" if relative.start_with?("/") || relative.split("/").include?("..")

        File.join(root, relative)
      end
    end
  end
end
