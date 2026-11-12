# frozen_string_literal: true

require "digest"
require "yaml"
require_relative "folder_name"

module Plastic
  module Graph
    module Knowledge
      class Backup
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

          def write_report(name, status:, goal:) = File.write(File.join(path(name), "status.yml"), { "status" => status, "goal" => goal }.to_yaml)

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
end
