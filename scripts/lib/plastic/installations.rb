# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "harnesses"
require_relative "installations/record"
require_relative "installations/recording"
require_relative "installations/removal"

module Plastic
  # What an install wrote into each harness, one record file per harness
  # under the home's installations folder. See docs/reference/harness-adapters.md.
  module Installations
    def self.folder(plastic_home) = File.join(plastic_home, "installations")

    def self.path(plastic_home, harness) = File.join(folder(plastic_home), "#{harness}.json")

    def self.recorded(plastic_home) = Harnesses.names.select { |name| File.file?(path(plastic_home, name)) }

    def self.read(plastic_home, harness)
      file = path(plastic_home, harness)
      Record.from_h(JSON.parse(File.read(file))) if File.file?(file)
    end

    def self.write(plastic_home, record)
      FileUtils.mkdir_p(folder(plastic_home))
      File.write(path(plastic_home, record.harness), "#{JSON.pretty_generate(record.to_h)}\n")
    end

    def self.record(installer, keys)
      keys.filter_map { |key| Harnesses.installed_by(key) }.each { |harness| write(installer.plastic_home, Recording.new(installer, harness).call) }
    end

    def self.delete(plastic_home, harness) = FileUtils.rm_f(path(plastic_home, harness))
  end
end
