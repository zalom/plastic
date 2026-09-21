# frozen_string_literal: true

require_relative "sqlite"

module Plastic
  module SearchIndex
    NAME = "knowledge_graph.db"
    SCHEMA = <<~SQL
      CREATE TABLE doc(id INTEGER PRIMARY KEY, path TEXT, sz INT, data BLOB);
      CREATE VIEW doc_v AS SELECT id AS rowid, CAST(sqlar_uncompress(data, sz) AS TEXT) AS body FROM doc;
      CREATE VIRTUAL TABLE ft USING fts5(body, content='doc_v', content_rowid='rowid');
    SQL
    FINISH = "INSERT INTO ft(ft) VALUES('rebuild'); INSERT INTO ft(ft) VALUES('optimize'); VACUUM;"

    def self.path(home)
      File.join(home, NAME)
    end

    def self.files(home)
      Dir.glob("{store,projects}/**/*.md", File::FNM_DOTMATCH, base: home).reject { |file| file.include?("/.git/") }.sort
    end

    def self.build(home)
      files = files(home)
      draft = "#{path(home)}.tmp"
      File.delete(draft) if File.exist?(draft)
      Sqlite.call(draft, [SCHEMA, "BEGIN;", *files.map { |file| insert(home, file) }, "COMMIT;", FINISH].join("\n"))
      File.rename(draft, path(home))
      files.size
    ensure
      File.delete(draft) if draft && File.exist?(draft)
    end

    def self.insert(home, file)
      source = quote(File.join(home, file))
      "INSERT INTO doc(path, sz, data) VALUES(#{quote(file)}, length(readfile(#{source})), sqlar_compress(readfile(#{source})));"
    end

    def self.search(home, terms, limit:, prefix: "")
      phrases = terms.map { |term| %("#{term.delete('"')}") }.join(" ")
      Sqlite.call(path(home), <<~SQL, readonly: true)
        SELECT doc.path AS path, snippet(ft, 0, '[', ']', ' ... ', 12) AS excerpt
        FROM ft JOIN doc ON doc.id = ft.rowid
        WHERE ft MATCH #{quote(phrases)} AND doc.path LIKE #{quote("#{prefix}%")}
        ORDER BY rank LIMIT #{Integer(limit)};
      SQL
    end

    def self.quote(text)
      "'#{text.gsub("'", "''")}'"
    end
  end
end
