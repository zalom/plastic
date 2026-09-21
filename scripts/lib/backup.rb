# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "tmpdir"
require "zlib"
require_relative "store_sync"

module Plastic
  module Backup
    DATABASES = [SearchIndex::NAME, WorkGraph::NAME, ReferenceArchive::NAME].freeze
    ROOT_FILES = %w[config.yml projects.yml INDEX.md].freeze
    Missing = Class.new(StandardError)

    def self.dir(home)
      File.join(home, "backups")
    end

    def self.list(home)
      Dir.glob(File.join(dir(home), "plastic-backup--*.tar.gz")).sort
    end

    def self.call(home, version:, now: Time.now.utc)
      missing = DATABASES.reject { |name| File.exist?(File.join(home, name)) }
      raise Missing, missing.join(", ") unless missing.empty?

      Dir.mktmpdir("plastic-backup") do |work|
        DATABASES.each { |name| Sqlite.call(File.join(home, name), "VACUUM INTO #{Sqlite.quote(File.join(work, name))};", readonly: true) }
        FileUtils.cp(ROOT_FILES.map { |name| File.join(home, name) }.select { |path| File.exist?(path) }, work)
        File.write(File.join(work, "manifest.json"), JSON.pretty_generate(manifest(work, version, now)))
        pack(work, File.join(dir(home), "plastic-backup--#{now.strftime("%Y%m%dT%H%M%SZ")}.tar.gz"))
      end
    end

    def self.manifest(work, version, now)
      files = Dir.children(work).sort.map do |name|
        path = File.join(work, name)
        {"name" => name, "bytes" => File.size(path), "sha256" => Digest::SHA256.file(path).hexdigest}
      end
      {"version" => version, "at" => now.strftime("%Y-%m-%dT%H:%M:%SZ"), "files" => files}
    end

    def self.pack(work, archive)
      require "rubygems"
      require "rubygems/package"
      FileUtils.mkdir_p(File.dirname(archive))
      draft = "#{archive}.tmp"
      Zlib::GzipWriter.open(draft) do |gzip|
        Gem::Package::TarWriter.new(gzip) do |tar|
          Dir.children(work).sort.each do |name|
            path = File.join(work, name)
            tar.add_file_simple(name, 0o644, File.size(path)) { |entry| IO.copy_stream(path, entry) }
          end
        end
      end
      File.rename(draft, archive)
      archive
    ensure
      FileUtils.rm_f(draft.to_s)
    end
  end
end
