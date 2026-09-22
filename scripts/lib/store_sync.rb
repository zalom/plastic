# frozen_string_literal: true

require "open3"
require "tempfile"
require_relative "search_index"
require_relative "reference_archive"
require_relative "work_graph"

module Plastic
  module StoreSync
    INTENT_PATH = %r{\A(?:(?:projects|stores)/([^/]+)/)?store/([^/]+?)--}
    ROW_HASH = "lower(hex(sha3(sqlar_uncompress(data, sz), 256)))"

    def self.action(state)
      file, row, recorded = state.values_at("file", "row", "hash")
      return "write" if file.nil?
      return if file == row
      return "read" if row == recorded
      return "write" if file == recorded

      "conflict"
    end

    def self.plan(home)
      known = states(home)
      fresh = SearchIndex.files(home) - known.map { |state| state["path"] }
      plan = known.map { |state| [action(state), state["path"]] } + fresh.map { |file| ["read", file] }
      plan.select(&:first).sort_by(&:last)
    end

    def self.states(home)
      Sqlite.call(SearchIndex.path(home), <<~SQL, readonly: true)
        SELECT path, lower(hex(sha3(readfile(#{Sqlite.quote(home)} || '/' || path), 256))) AS file, #{ROW_HASH} AS row, hash
        FROM doc;
      SQL
    end

    def self.apply(home, plan)
      statements = plan.map { |action, path| send(action, home, path) }
      statements << "INSERT INTO ft(ft) VALUES('rebuild');" if plan.any? { |action, _path| action == "read" }
      Sqlite.call(SearchIndex.path(home), ["BEGIN;", *statements, "COMMIT;"].join("\n"))
    end

    def self.read(home, path)
      "DELETE FROM doc WHERE path = #{Sqlite.quote(path)};\n#{SearchIndex.insert(home, path)}"
    end

    def self.write(home, path)
      where = "WHERE path = #{Sqlite.quote(path)}"
      "#{restore(home, "doc", "path")} #{where};\nUPDATE doc SET hash = #{ROW_HASH} #{where};"
    end

    def self.restore(home, table, column)
      "SELECT writefile(#{Sqlite.quote(home)} || '/' || #{column}, sqlar_uncompress(data, sz)) FROM #{table}"
    end

    def self.diff(home, path)
      body = Sqlite.call(SearchIndex.path(home), <<~SQL, readonly: true).first["body"]
        SELECT CAST(sqlar_uncompress(data, sz) AS TEXT) AS body FROM doc WHERE path = #{Sqlite.quote(path)};
      SQL
      Tempfile.create("plastic-row") do |row|
        row.write(body)
        row.flush
        Open3.capture2("diff", "-u", "-L", "row", "-L", "file", row.path, File.join(home, path)).first
      end
    end

    def self.orphans(home)
      paths = Sqlite.call(SearchIndex.path(home), "SELECT path FROM doc;", readonly: true) +
        Sqlite.call(ReferenceArchive.path(home), "SELECT name AS path FROM sqlar;", readonly: true)
      keys = paths.filter_map { |row| row["path"].match(INTENT_PATH) }.map { |found| "#{found[1] || "global"}:#{found[2]}" }
      (keys.uniq - WorkGraph.known(home)).sort
    end

    def self.checkout(home)
      {SearchIndex.path(home) => %w[doc path], ReferenceArchive.path(home) => %w[sqlar name]}.flat_map do |database, (table, column)|
        missing = Sqlite.call(database, "SELECT #{column} AS path FROM #{table};", readonly: true)
          .map { |row| row["path"] }.reject { |path| File.exist?(File.join(home, path)) }
        names = missing.map { |path| Sqlite.quote(path) }.join(", ")
        Sqlite.call(database, "#{restore(home, table, column)} WHERE #{column} IN (#{names});", readonly: true)
        missing
      end
    end
  end
end
