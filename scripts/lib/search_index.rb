# frozen_string_literal: true

require "fileutils"
require_relative "sqlite"

module Plastic
  module SearchIndex
    NAME = "knowledge_graph.db"
    SCHEMA = <<~SQL
      CREATE TABLE doc(id INTEGER PRIMARY KEY, path TEXT, sz INT, data BLOB, hash TEXT);
      CREATE VIEW doc_v AS SELECT id AS rowid, CAST(sqlar_uncompress(data, sz) AS TEXT) AS body FROM doc;
      CREATE VIRTUAL TABLE ft USING fts5(body, content='doc_v', content_rowid='rowid');
    SQL
    FINISH = "INSERT INTO ft(ft) VALUES('rebuild'); INSERT INTO ft(ft) VALUES('optimize'); VACUUM;"

    def self.path(home)
      File.join(home, NAME)
    end

    def self.files(home)
      Dir.glob("{store,projects,stores}/**/*.md", File::FNM_DOTMATCH, base: home).reject { |file| file.include?("/.git/") }.sort
    end

    def self.build(home)
      files = files(home)
      draft = "#{path(home)}.tmp"
      FileUtils.rm_f(draft)
      Sqlite.call(draft, [SCHEMA, "BEGIN;", *files.map { |file| insert(home, file) }, "COMMIT;", FINISH].join("\n"))
      File.rename(draft, path(home))
      files.size
    ensure
      FileUtils.rm_f(draft.to_s)
    end

    def self.insert(home, file)
      source = quote(File.join(home, file))
      "INSERT INTO doc(path, sz, data, hash) VALUES(#{quote(file)}, length(readfile(#{source})), " \
        "sqlar_compress(readfile(#{source})), lower(hex(sha3(readfile(#{source}), 256))));"
    end

    def self.search(home, terms, limit:, prefix: "")
      phrases = terms.map { |term| %("#{term.delete('"')}") }.join(" ")
      Sqlite.call(path(home), <<~SQL, readonly: true)
        SELECT doc.id AS id, doc.path AS path, snippet(ft, 0, '[', ']', ' ... ', 12) AS excerpt
        FROM ft JOIN doc ON doc.id = ft.rowid
        WHERE ft MATCH #{quote(phrases)} AND doc.path LIKE #{quote("#{prefix}%")}
        ORDER BY rank LIMIT #{Integer(limit)};
      SQL
    end

    def self.quote(text)
      Sqlite.quote(text)
    end
  end
end
