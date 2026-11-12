# frozen_string_literal: true

require "fileutils"
require_relative "../archive"
require_relative "tree"
require_relative "../../sql"

module Plastic
  module Graph
    module Knowledge
      class Archive
        # Compares, stores and writes the saved rows of an archive snapshot.
        # Each row is a Hash with path, kind, mode, mtime and data.
        module Entries
          STRICT = %i[path kind mode mtime data].freeze
          LOOSE = %i[path kind mode data].freeze

          def self.stored(entry, intent_id)
            data = entry[:data]
            entry.merge(intent_id:, data: data && SQL::Bytes.new(data))
          end

          def self.fields(entry) = (entry[:kind] == "directory") ? LOOSE : STRICT

          def self.changed(current, saved) = current.find { |entry| !match?(entry, saved, fields(entry)) }

          def self.match?(entry, saved, fields)
            row = saved.find { |candidate| candidate[:path] == entry[:path] }
            row && fields.all? { |key| entry[key] == row[key] }
          end

          def self.same?(current, saved) = current.size == saved.size && current.all? { |entry| match?(entry, saved, STRICT) }

          def self.depth(row) = row[:path].count("/")

          def self.located(root, relative)
            raise Tree::Error, "invalid archive path #{relative}" if relative.start_with?("/") || relative.split("/").include?("..")

            File.join(root, relative)
          end

          def self.build(stage, saved)
            saved.sort_by { |row| depth(row) }
              .each { |row| write(stage, row) }
              .reverse_each { |row| settle(stage, row) }
          end

          def self.write(stage, row)
            target = located(stage, row[:path])
            case row
            in { kind: "directory" } then FileUtils.mkdir_p(target)
            in { kind: "file", data: } then File.binwrite(target, data)
            in { kind: "link", data: } then File.symlink(data, target)
            else raise Tree::Error, "invalid archive entry kind #{row[:kind]}"
            end
          end

          def self.settle(stage, row)
            row => { path:, mtime: }
            target = located(stage, path)
            chmod(target, row)
            time = Time.at(Rational(mtime))
            File.lutime(time, time, target)
          end

          def self.chmod(target, row)
            mode = row[:mode]
            return File.chmod(mode, target) unless row[:kind] == "link"

            File.lchmod(mode, target) if File.lstat(target).mode & 0o7777 != mode
          end
        end
      end
    end
  end
end
