# frozen_string_literal: true

require "digest"
require "fileutils"
require "yaml"
require_relative "folder_name"

module Plastic
  module Graph
    module Backup
      # The backup folders of one store on disk. The folders decide what
      # backups exist.
      class Folders
        attr_reader :dir

        def initialize(store_root)
          @dir = File.join(store_root, "backups")
        end

        def names
          return [] unless File.directory?(dir)

          Dir.children(dir).grep(FolderName::PATTERN).select { |name| File.directory?(path(name)) }.sort
        end

        def latest = names.last

        def path(name) = File.join(dir, name)

        def exist?(name) = names.include?(name)

        def status(name) = report(name).fetch("status", "unknown")

        def goal(name) = report(name).fetch("goal", "unknown")

        def report(name)
          file = File.join(path(name), "status.yml")
          File.file?(file) ? (YAML.safe_load_file(file) || {}) : {}
        end

        def write_report(name, status:, goal:, **extra) = File.write(File.join(path(name), "status.yml"), { "status" => status, "goal" => goal }.merge(extra.transform_keys(&:to_s)).to_yaml)

        # Adds the digest of the folder's files to its status file.
        def record_digest(name) = File.write(File.join(path(name), "status.yml"), report(name).merge("digest" => digest(name)).to_yaml)

        # The verdict of the newest check of the live files: time, verdict, and for a failure the file and the reason.
        def last_check
          file = File.join(dir, "last-check.yml")
          File.file?(file) ? (YAML.safe_load_file(file) || {}) : {}
        end

        def write_check(**check)
          FileUtils.mkdir_p(dir)
          File.write(File.join(dir, "last-check.yml"), check.compact.transform_keys(&:to_s).to_yaml)
        end

        def files(name) = Dir.children(path(name)).grep(/\.db\z/).sort

        def bytes(name) = files(name).sum { |file| File.size(File.join(path(name), file)) }

        # The digest of the sorted list of each file's name and digest.
        def digest(name)
          lines = files(name).map { |file| "#{file} #{Digest::SHA256.file(File.join(path(name), file)).hexdigest}" }
          Digest::SHA256.hexdigest(lines.join("\n"))
        end
      end
    end
  end
end
