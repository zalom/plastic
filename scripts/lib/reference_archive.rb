# frozen_string_literal: true

require "digest"
require_relative "sqlite"

module Plastic
  module ReferenceArchive
    NAME = "references.db"
    SCHEMA = <<~SQL
      CREATE TABLE IF NOT EXISTS sqlar(name TEXT PRIMARY KEY, mode INT, mtime INT, sz INT, data BLOB, intent_id TEXT, sha256 TEXT);
    SQL
    INTENT_ID = %r{/([^/-]+)--[^/]+/resources/}

    def self.path(home)
      File.join(home, NAME)
    end

    def self.files(home)
      Dir.glob("{store,projects}/**/resources/**/*", File::FNM_DOTMATCH, base: home)
        .select { |file| File.file?(File.join(home, file)) && File.extname(file) != ".md" }.sort
    end

    def self.build(home)
      known = Sqlite.call(path(home), "#{SCHEMA}SELECT name, mtime, sz FROM sqlar;").to_h { |row| [row["name"], row.values_at("mtime", "sz")] }
      changed = files(home).reject { |file| known[file] == stamp(File.join(home, file)) }
      Sqlite.call(path(home), ["BEGIN;", *changed.map { |file| insert(home, file) }, "COMMIT;"].join("\n"))
      changed.size
    end

    def self.stamp(source)
      stat = File.stat(source)
      [stat.mtime.to_i, stat.size]
    end

    def self.insert(home, file)
      source = File.join(home, file)
      stat = File.stat(source)
      id = file[INTENT_ID, 1]
      read = "readfile(#{Sqlite.quote(source)})"
      "INSERT OR REPLACE INTO sqlar VALUES(#{Sqlite.quote(file)}, #{stat.mode}, #{stat.mtime.to_i}, length(#{read}), " \
        "sqlar_compress(#{read}), #{id ? Sqlite.quote(id) : "NULL"}, #{Sqlite.quote(Digest::SHA256.file(source).hexdigest)});"
    end
  end
end
