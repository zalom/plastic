# frozen_string_literal: true

require "digest"
require "fileutils"
require "yaml"
require_relative "folder_name"
require_relative "yaml_file"

module Plastic
  module Graph
    module Backup
      # The backup folders of one store on disk. The folders decide what
      # backups exist.
      class Folders
        NAME = "backups"
        # How long a backup may stay in-progress before it counts as left by a stopped run; a newer one is another session's live claim.
        CLAIM_WINDOW = 5 * 60

        attr_reader :dir

        def initialize(store_root)
          @dir = File.join(store_root, NAME)
        end

        def names
          return [] unless File.directory?(dir)

          Dir.children(dir).grep(FolderName::PATTERN).select { |name| File.directory?(path(name)) }.sort
        end

        # The newest folder whose name is a real time and that the block accepts, or nil; a name that is not a real time has no age to judge.
        def latest = names.reverse.find { |name| FolderName.readable?(name) && (!block_given? || yield(name)) }

        def path(name) = File.join(dir, name)

        def exist?(name) = names.include?(name)

        def status(name) = report(name).fetch("status", "unknown")

        def goal(name) = report(name).fetch("goal", "unknown")

        def report(name)
          YamlFile.hash(File.join(path(name), "status.yml"))
        end

        def write_report(name, status:, goal:, **extra) = File.write(File.join(path(name), "status.yml"), { "status" => status, "goal" => goal }.merge(extra.transform_keys(&:to_s)).to_yaml)

        # Adds the digest of the folder's files to its status file.
        def record_digest(name) = File.write(File.join(path(name), "status.yml"), report(name).merge("digest" => digest(name)).to_yaml)

        # The verdict of the newest check of the live files: time, verdict, and for a failure the file and the reason.
        def last_check = YamlFile.hash(File.join(dir, "last-check.yml"))

        def write_check(**check)
          FileUtils.mkdir_p(dir)
          File.write(File.join(dir, "last-check.yml"), check.compact.transform_keys(&:to_s).to_yaml)
        end

        def files(name) = Dir.children(path(name)).grep(/\.db\z/).sort

        # The file count, the byte count and the digest of one backup folder.
        def summary(name)
          listed = files(name)
          { files: listed.size, bytes: listed.sum { |file| File.size(File.join(path(name), file)) }, sha256: digest(name) }
        end

        # The digest of the sorted list of each file's name and digest.
        def digest(name)
          lines = files(name).map { |file| "#{file} #{Digest::SHA256.file(File.join(path(name), file)).hexdigest}" }
          Digest::SHA256.hexdigest(lines.join("\n"))
        end
      end
    end
  end
end
